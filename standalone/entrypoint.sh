#!/bin/sh

RUN_AS_USER=${RUN_AS_USER:-sds}
WORK_DIR=${WORK_DIR:-/sds}
NETWORK_PORT=${NETWORK_PORT:-18081}
PPD_BIN=/usr/bin/ppd
RPCCLIENT_BIN=/usr/bin/rpcclient
RPC_URL=${RPC_URL:-http://127.0.0.1:18281}
RPC_PASSWORD=${RPC_PASSWORD:-}
DOWNLOAD_FILENAME=${DOWNLOAD_FILENAME:-latest}

# Default mnemonic phrase (can be overridden via environment variable)
DEFAULT_MNEMONIC="believe devote local make usual emotion glare mushroom fashion opinion flush scout travel uniform private sing hollow slam mirror trip clump exist clutch audit"
MNEMONIC_PHRASE=${MNEMONIC_PHRASE:-$DEFAULT_MNEMONIC}

# Default wallet address (can be overridden via environment variable)
WALLET_ADDRESS=${WALLET_ADDRESS:-st1g0ljrfqp3d87hxtp5gx52lu0lh0le59475xz42}

# Auto-detect public IP if not provided
if [ -z "${NETWORK_ADDRESS}" ]; then
    echo "[entrypoint] NETWORK_ADDRESS not set, auto-detecting public IP..."
    NETWORK_ADDRESS=$(curl -4 -s ip.me)
    if [ -z "$NETWORK_ADDRESS" ]; then
        echo "Error: Failed to auto-detect public IP. Please set NETWORK_ADDRESS manually." >&2
        exit 1
    fi
    echo "[entrypoint] Detected public IP: $NETWORK_ADDRESS"
fi

# Initialize if needed
if [ ! -d "$WORK_DIR/config" ]
then

  echo "[entrypoint] Init SDS resource node..."
  printf "\n\n3\n" | $PPD_BIN config --create-p2p-key --home $WORK_DIR
  printf "\n" | $PPD_BIN config accounts --mnemonic "$MNEMONIC_PHRASE" --home $WORK_DIR

  echo "[entrypoint] Set network_address to '$NETWORK_ADDRESS'"
  sed -i '/\[node\.connectivity\]/,/^\[/ {/network_address/ s/= .*/= '\'$NETWORK_ADDRESS\''/}' $WORK_DIR/config/config.toml

  echo "[entrypoint] Set network_port to $NETWORK_PORT"
  sed -i '/\[node\.connectivity\]/,/^\[/ {/network_port/ s/= .*/= '\'$NETWORK_PORT\''/}' $WORK_DIR/config/config.toml

  RPC_NAMESPACES=${RPC_NAMESPACES:-user,owner}
  echo "[entrypoint] Set rpc_namespaces to '$RPC_NAMESPACES'"
  sed -i "s/rpc_namespaces = 'user'/rpc_namespaces = '$RPC_NAMESPACES'/" $WORK_DIR/config/config.toml
fi

chown -R $RUN_AS_USER $WORK_DIR
echo "[entrypoint] Starting as user: $RUN_AS_USER"

# Start ppd in background
gosu "$RUN_AS_USER" ppd start &
PPD_PID=$!

# Wait for node to be ready (check if RPC port is listening)
echo "[entrypoint] Waiting for node to be ready..."
MAX_WAIT=60
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if nc -z 127.0.0.1 18281 2>/dev/null; then
        echo "[entrypoint] ✓ Node is ready (RPC port 18281 is listening)"
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
        echo "[entrypoint] Still waiting... ($WAIT_COUNT seconds)"
    fi
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo "[entrypoint] ✗ Timeout waiting for node to be ready"
    kill $PPD_PID 2>/dev/null
    exit 1
fi

# Register peer
echo "[entrypoint] Registering peer..."
RP_OUTPUT=$(gosu "$RUN_AS_USER" $RPCCLIENT_BIN -p "$RPC_PASSWORD" -u "$RPC_URL" rp 2>&1)

if echo "$RP_OUTPUT" | grep -q "return: SUCCESS"; then
    echo "[entrypoint] ✓ Peer registered successfully"
elif echo "$RP_OUTPUT" | grep -q "return:  -10"; then
    echo "[entrypoint] ✓ Peer already registered"
else
    echo "[entrypoint] ✗ Failed to register peer"
    echo "$RP_OUTPUT"
    kill $PPD_PID 2>/dev/null
    exit 1
fi

# Get file list
echo "[entrypoint] Fetching file list..."
FILE_LIST=$(gosu "$RUN_AS_USER" $RPCCLIENT_BIN -p "$RPC_PASSWORD" -u "$RPC_URL" list 2>&1)

if [ "$DOWNLOAD_FILENAME" = "latest" ]; then
    echo "[entrypoint] Finding latest snapshot..."
    # Find the most recent .tar file
    MOST_RECENT_FILE=$(echo "$FILE_LIST" | \
        grep ".tar" | \
        awk 'NF>=4 {print $0}' | \
        sort -k4 -n -r | \
        head -n 1)
    
    if [ -z "$MOST_RECENT_FILE" ]; then
        echo "[entrypoint] ✗ No .tar files found"
        kill $PPD_PID 2>/dev/null
        exit 1
    fi
    
    FILENAME=$(echo "$MOST_RECENT_FILE" | awk '{print $1}')
    FILEHASH=$(echo "$MOST_RECENT_FILE" | awk '{print $2}')
    TIMESTAMP=$(echo "$MOST_RECENT_FILE" | awk '{print $4}')
    
    echo "[entrypoint] Latest file: $FILENAME (timestamp: $TIMESTAMP)"
else
    echo "[entrypoint] Looking for file: $DOWNLOAD_FILENAME"
    FILEHASH=$(echo "$FILE_LIST" | \
        grep -F "$DOWNLOAD_FILENAME" | \
        awk '{print $2}')
    
    if [ -z "$FILEHASH" ]; then
        echo "[entrypoint] ✗ File '$DOWNLOAD_FILENAME' not found"
        kill $PPD_PID 2>/dev/null
        exit 1
    fi
    
    FILENAME="$DOWNLOAD_FILENAME"
fi

# Download with retry logic
echo "[entrypoint] Downloading $FILENAME (hash: $FILEHASH)..."

MAX_RETRIES=5
RETRY_COUNT=0
DOWNLOAD_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
        echo "[entrypoint] Retry attempt $RETRY_COUNT of $MAX_RETRIES..."
    fi
    
    DOWNLOAD_OUTPUT=$(gosu "$RUN_AS_USER" $RPCCLIENT_BIN -p "$RPC_PASSWORD" -u "$RPC_URL" get "sdm://${WALLET_ADDRESS}/${FILEHASH}" 2>&1)
    
    # Check if download was successful
    if echo "$DOWNLOAD_OUTPUT" | grep -q "return:  -5"; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "[entrypoint] ⚠ Download failed (response code: -5), retrying..."
            sleep 2
        else
            echo "[entrypoint] ✗ Download failed after $MAX_RETRIES attempts (response code: -5)"
            kill $PPD_PID 2>/dev/null
            exit 1
        fi
    else
        DOWNLOAD_SUCCESS=true
        break
    fi
done

if [ "$DOWNLOAD_SUCCESS" = true ]; then
    echo "[entrypoint] ✓ Download completed successfully"
    echo "[entrypoint] File location: $WORK_DIR/download/$FILENAME"
fi

# Cleanup and exit
echo "[entrypoint] Shutting down node..."
kill $PPD_PID 2>/dev/null
wait $PPD_PID 2>/dev/null

echo "[entrypoint] Done!"
exit 0

