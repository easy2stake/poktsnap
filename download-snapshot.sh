#!/usr/bin/env bash

# Load configuration from .env file
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found"
    exit 1
fi

# Check argument
if [ -z "$1" ]; then
    echo "Usage: $0 <filename|latest>"
    echo "  filename - Download a specific file by name"
    echo "  latest   - Download the most recent file (by timestamp)"
    exit 1
fi

FILENAME="$1"

# Check peer registration status
echo "Checking peer registration status..."
RP_OUTPUT=$(docker exec sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" rp 2>&1)

if echo "$RP_OUTPUT" | grep -q "return: SUCCESS"; then
    echo "✓ Peer registered successfully"
elif echo "$RP_OUTPUT" | grep -q "return:  -10"; then
    echo "✓ Peer already registered"
else
    echo "Error: Failed to register peer"
    echo "$RP_OUTPUT"
    exit 1
fi
echo ""

# Get the full file list
FILE_LIST=$(docker exec sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list)

if [ "$FILENAME" = "latest" ]; then
    # Find the file with the highest timestamp (4th column)
    # Filter for tar files only and sort by timestamp
    MOST_RECENT_FILE=$(echo "$FILE_LIST" | \
        grep ".tar" | \
        awk 'NF>=4 {print $0}' | \
        sort -k4 -n -r | \
        head -n 1)
    
    if [ -z "$MOST_RECENT_FILE" ]; then
        echo "Error: No files found in list"
        exit 1
    fi
    
    FILENAME=$(echo "$MOST_RECENT_FILE" | awk '{print $1}')
    FILEHASH=$(echo "$MOST_RECENT_FILE" | awk '{print $2}')
    TIMESTAMP=$(echo "$MOST_RECENT_FILE" | awk '{print $4}')
    
    echo "Latest file found: $FILENAME (timestamp: $TIMESTAMP)"
else
    # Get file list and extract hash for matching filename
    FILEHASH=$(echo "$FILE_LIST" | \
        grep -F "$FILENAME" | \
        awk '{print $2}')
    
    # Check if file was found
    if [ -z "$FILEHASH" ]; then
        echo "Error: File '$FILENAME' not found in list"
        exit 1
    fi
fi

# Download the file
echo "Downloading $FILENAME (hash: $FILEHASH)..."
docker exec -it sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" get "sdm://${WALLET_ADDRESS}/${FILEHASH}"

