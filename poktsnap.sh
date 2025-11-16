#!/usr/bin/env bash

# ============================================================================
# poktsnap.sh - Combined CLI for snapshot management
# ============================================================================

# Load configuration from .env file
load_env() {
    if [ -f .env ]; then
        source .env
    else
        echo "Error: .env file not found"
        exit 1
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  list                          List all files in SDS node"
    echo "  download <filename|latest>    Download a file (by name or latest)"
    echo "  upload <file-path>            Upload a file to SDS node"
    echo "  delete <filehash>             Delete a file from SDS node by hash"
    echo "  shell                         Open bash shell inside container as sds user"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 download latest"
    echo "  $0 download myfile.tar"
    echo "  $0 upload /path/to/snapshot.tar"
    echo "  $0 delete v05ahm51csphdaga08tnbu6pck97rs4fls8i2i03"
    echo "  $0 shell"
}

# ============================================================================
# Command: list
# ============================================================================
cmd_list() {
    load_env
    
    echo "Fetching file list from SDS node..."
    echo ""
    
    docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list
}

# ============================================================================
# Command: download
# ============================================================================
cmd_download() {
    load_env
    
    # Check argument
    if [ -z "$1" ]; then
        echo "Error: Missing filename argument"
        echo ""
        echo "Usage: $0 download <filename|latest>"
        echo "  filename - Download a specific file by name"
        echo "  latest   - Download the most recent file (by timestamp)"
        exit 1
    fi
    
    FILENAME="$1"
    
    # Get the full file list
    FILE_LIST=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list)
    
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
    
    # Download the file with retry logic
    echo "Downloading $FILENAME (hash: $FILEHASH)..."
    
    MAX_RETRIES=5
    RETRY_COUNT=0
    DOWNLOAD_SUCCESS=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if [ $RETRY_COUNT -gt 0 ]; then
            echo ""
            echo "Retry attempt $RETRY_COUNT of $MAX_RETRIES..."
        fi
        
        DOWNLOAD_OUTPUT=$(docker exec -u sds -it sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" get "sdm://${WALLET_ADDRESS}/${FILEHASH}" 2>&1)
        echo "$DOWNLOAD_OUTPUT"
        
        # Check if download was successful
        if echo "$DOWNLOAD_OUTPUT" | grep -q "return:  -5"; then
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "⚠ Download failed (response code: -5), retrying..."
                sleep 2
            else
                echo "✗ Download failed after $MAX_RETRIES attempts (response code: -5)"
                exit 1
            fi
        else
            DOWNLOAD_SUCCESS=true
            break
        fi
    done
    
    if [ "$DOWNLOAD_SUCCESS" = true ]; then
        echo ""
        echo "✓ Download completed successfully"
    fi
}

# ============================================================================
# Command: delete
# ============================================================================
cmd_delete() {
    load_env
    
    # Check argument
    if [ -z "$1" ]; then
        echo "Error: Missing filehash argument"
        echo ""
        echo "Usage: $0 delete <filehash>"
        echo "  filehash - Hash of the file to delete (use 'list' command to see hashes)"
        exit 1
    fi
    
    FILEHASH="$1"
    
    echo "Deleting file with hash: $FILEHASH"
    echo ""
    
    # Delete the file
    DELETE_OUTPUT=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" delete "$FILEHASH" 2>&1)
    echo "$DELETE_OUTPUT"
    
    # Check if delete was successful
    if echo "$DELETE_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
        echo ""
        echo "✓ File deleted successfully"
    else
        echo ""
        echo "✗ Delete may have failed. Please check the output above."
        exit 1
    fi
}

# ============================================================================
# Command: shell
# ============================================================================
cmd_shell() {
    echo "Opening bash shell in container as sds user..."
    echo ""
    
    docker exec -u sds -it sds-node bash
}

# ============================================================================
# Command: upload
# ============================================================================
cmd_upload() {
    load_env
    
    # Check argument
    if [ -z "$1" ]; then
        echo "Error: Missing file path argument"
        echo ""
        echo "Usage: $0 upload <file-path>"
        echo "  file-path - Path to the file you want to upload"
        exit 1
    fi
    
    FILEPATH="$1"
    
    # Check if file exists inside the container
    if ! docker exec -u sds sds-node test -f "$FILEPATH"; then
        echo "Error: File '$FILEPATH' not found inside container"
        exit 1
    fi
    
    echo "Uploading file: $FILEPATH"
    echo ""
    
    # Upload the file
    UPLOAD_OUTPUT=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" put "$FILEPATH" 2>&1)
    echo "$UPLOAD_OUTPUT"
    
    # Check if upload was successful
    if echo "$UPLOAD_OUTPUT" | grep -q "received response (return: SUCCESS)"; then
        echo ""
        echo "✓ Upload completed successfully"
        
        # Extract and display the file hash
        FILEHASH=$(echo "$UPLOAD_OUTPUT" | grep "File " | awk '{print $3}')
        if [ -n "$FILEHASH" ]; then
            echo "File hash: $FILEHASH"
        fi
    else
        echo ""
        echo "✗ Upload may have failed. Please check the output above."
        exit 1
    fi
}

# ============================================================================
# Main script logic
# ============================================================================

# Check if command is provided
if [ -z "$1" ]; then
    show_usage
    exit 1
fi

COMMAND="$1"
shift

# Route to appropriate command
case "$COMMAND" in
    list)
        cmd_list
        ;;
    download)
        cmd_download "$@"
        ;;
    upload)
        cmd_upload "$@"
        ;;
    delete)
        cmd_delete "$@"
        ;;
    shell)
        cmd_shell
        ;;
    -h|--help|help)
        show_usage
        exit 0
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        echo ""
        show_usage
        exit 1
        ;;
esac

