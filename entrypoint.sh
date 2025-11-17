#!/bin/sh

RUN_AS_USER=${RUN_AS_USER:-sds}
WORK_DIR=${WORK_DIR:-/sds}
NETWORK_PORT=${NETWORK_PORT:-18081}
PPD_BIN=/usr/bin/ppd
RPC_URL=${RPC_URL:-http://127.0.0.1:18281}
RPC_PASSWORD=${RPC_PASSWORD:-}

if [ ! -d "$WORK_DIR/config" ]
then
  if [ -z "${MNEMONIC_PHRASE}" ]; then
      echo "Error: The environment variable MNEMONIC_PHRASE is not set." >&2
      exit 1
  fi
  
  if [ -z "${NETWORK_ADDRESS}" ]; then
      echo "Error: The environment variable NETWORK_ADDRESS is not set." >&2
      exit 1
  fi

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

# Setup cron job for auto-upload monitoring
if [ -f /usr/local/bin/monitor-and-upload.sh ]; then
  echo "[entrypoint] Setting up auto-upload cron job..."
  
  # Create cron job that runs every 5 minutes
  # Pass environment variables to the script
  # Set PATH to include /usr/bin where rpcclient is located
  # Redirect to Docker's stdout/stderr so logs appear in docker logs
  echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" > /tmp/crontab.tmp
  echo "*/5 * * * * RPC_PASSWORD='$RPC_PASSWORD' RPC_URL='$RPC_URL' /usr/local/bin/monitor-and-upload.sh >> /proc/1/fd/1 2>>/proc/1/fd/2" >> /tmp/crontab.tmp  

 # Install crontab for the user
  crontab -u $RUN_AS_USER /tmp/crontab.tmp
  rm /tmp/crontab.tmp
  
  # Start cron daemon
  cron
  CRON_ENABLED=true
  
  echo "[entrypoint] Auto-upload cron job configured (runs every 5 minutes)"
else
  CRON_ENABLED=false
fi

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

# Register peer with retry logic
echo "[entrypoint] Registering peer..."
MAX_RP_RETRIES=12
RP_RETRY_COUNT=0
RP_SUCCESS=false

while [ $RP_RETRY_COUNT -lt $MAX_RP_RETRIES ]; do
    if [ $RP_RETRY_COUNT -gt 0 ]; then
        echo "[entrypoint] Retry attempt $RP_RETRY_COUNT of $MAX_RP_RETRIES..."
    fi
    
    RP_OUTPUT=$(gosu "$RUN_AS_USER" rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" rp 2>&1)
    
    if echo "$RP_OUTPUT" | grep -q "return: SUCCESS"; then
        echo "[entrypoint] ✓ Peer registered successfully"
        RP_SUCCESS=true
        break
    elif echo "$RP_OUTPUT" | grep -q "return:  -10"; then
        echo "[entrypoint] ✓ Peer already registered"
        RP_SUCCESS=true
        break
    else
        RP_RETRY_COUNT=$((RP_RETRY_COUNT + 1))
        if [ $RP_RETRY_COUNT -lt $MAX_RP_RETRIES ]; then
            # Check if it's a connection issue (return -5)
            if echo "$RP_OUTPUT" | grep -q "return:  -5"; then
                echo "[entrypoint] ⚠ Node is connecting to SP network, waiting 5 seconds before retry..."
                sleep 5
            else
                echo "[entrypoint] ⚠ Peer registration failed, retrying in 5 seconds..."
                sleep 5
            fi
        fi
    fi
done

if [ "$RP_SUCCESS" = false ]; then
    echo "[entrypoint] ✗ Failed to register peer after $MAX_RP_RETRIES attempts"
    echo "[entrypoint] Last error output:"
    echo "$RP_OUTPUT"
    kill $PPD_PID 2>/dev/null
    exit 1
fi

# Setup signal handling for graceful shutdown
shutdown() {
    echo "[entrypoint] Received shutdown signal, stopping services..."
    
    # Stop ppd
    kill -TERM $PPD_PID 2>/dev/null
    wait $PPD_PID 2>/dev/null
    
    # Stop cron if it was enabled
    if [ "$CRON_ENABLED" = "true" ]; then
        pkill -TERM cron 2>/dev/null
    fi
    
    echo "[entrypoint] Shutdown complete"
    exit 0
}

trap shutdown SIGTERM SIGINT

# Keep container running by waiting on ppd process
wait $PPD_PID
