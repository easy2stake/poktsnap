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
    echo "Usage: $0 <filename>"
    exit 1
fi

FILENAME="$1"

# Get file list and extract hash for matching filename
FILEHASH=$(docker exec sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list | \
    grep -F "$FILENAME" | \
    awk '{print $2}')

# Check if file was found
if [ -z "$FILEHASH" ]; then
    echo "Error: File '$FILENAME' not found in list"
    exit 1
fi

# Download the file
echo "Downloading $FILENAME (hash: $FILEHASH)..."
docker exec -it sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" get "sdm://${WALLET_ADDRESS}/${FILEHASH}"

