#!/usr/bin/env bash

# ============================================================================
# poktsnap.sh - Combined CLI for snapshot management
# ============================================================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "  list [-a|--all]               List files in SDS node"
    echo "                                  -a, --all: Show all files (default: .tar only)"
    echo "  download <filename|latest>    Download a file (by name or latest)"
    echo "  upload <file-path>            Upload a file to SDS node"
    echo "  delete <filehash>             Delete a file from SDS node by hash"
    echo "  shell                         Open bash shell inside container as sds user"
    echo ""
    echo "Examples:"
    echo "  $0 list                       # List .tar files only"
    echo "  $0 list --all                 # List all files"
    echo "  $0 download latest"
    echo "  $0 download myfile.tar"
    echo "  $0 upload /path/to/snapshot.tar"
    echo "  $0 delete v05ahm51csphdaga08tnbu6pck97rs4fls8i2i03"
    echo "  $0 shell"
}

# Format file size to human-readable format (bytes -> MB/GB)
format_size() {
    local size="$1"
    
    if [ -z "$size" ] || ! [ "$size" -gt 0 ] 2>/dev/null; then
        echo "$size"
        return
    fi
    
    if [ "$size" -gt 1073741824 ]; then
        awk "BEGIN {printf \"%.2f GB\", $size/1073741824}"
    elif [ "$size" -gt 1048576 ]; then
        awk "BEGIN {printf \"%.2f MB\", $size/1048576}"
    else
        echo "${size} bytes"
    fi
}

# Format Unix timestamp to readable date
format_timestamp() {
    local timestamp="$1"
    
    if [ -n "$timestamp" ] && [ "$timestamp" -gt 0 ] 2>/dev/null; then
        date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$timestamp"
    else
        echo "$timestamp"
    fi
}

# ============================================================================
# Command: list
# ============================================================================
cmd_list() {
    load_env
    
    local SHOW_ALL=false
    
    # Check for --all or -a flag
    if [ "$1" = "--all" ] || [ "$1" = "-a" ]; then
        SHOW_ALL=true
    fi
    
    echo "Fetching file list from SDS node..."
    echo ""
    
    # Get file list
    FILE_LIST=$(docker exec -u sds sds-node rpcclient -p "$RPC_PASSWORD" -u "$RPC_URL" list 2>&1)
    
    # Filter based on flag
    if [ "$SHOW_ALL" = true ]; then
        # Show all files (exclude only debug lines)
        FILES=$(echo "$FILE_LIST" | grep -v "^\[DEBUG\]" | awk 'NF>=4 {print $0}' | sort -k4 -n -r)
        FILE_TYPE="All Files"
    else
        # Show only .tar files (default)
        FILES=$(echo "$FILE_LIST" | grep -v "^\[DEBUG\]" | grep "\.tar" | awk 'NF>=4 {print $0}' | sort -k4 -n -r)
        FILE_TYPE="Snapshot Files (.tar)"
    fi
    
    if [ -z "$FILES" ]; then
        echo "No files found."
        return
    fi
    
    echo "=========================================="
    echo "$FILE_TYPE"
    echo "=========================================="
    echo ""
    
    # Print header
    printf "%-50s %-45s %-12s %-20s\n" "FILENAME" "HASH" "SIZE" "TIMESTAMP"
    printf "%-50s %-45s %-12s %-20s\n" "--------" "----" "----" "---------"
    
    # Print each file
    echo "$FILES" | while IFS= read -r line; do
        FNAME=$(echo "$line" | awk '{print $1}')
        FHASH=$(echo "$line" | awk '{print $2}')
        FSIZE=$(echo "$line" | awk '{print $3}')
        FTIME=$(echo "$line" | awk '{print $4}')
        
        FDATE=$(format_timestamp "$FTIME")
        FSIZE_DISPLAY=$(format_size "$FSIZE")
        
        printf "%-50s %-45s %-12s %-20s\n" "$FNAME" "$FHASH" "$FSIZE_DISPLAY" "$FDATE"
    done
    
    echo ""
    echo "Total files: $(echo "$FILES" | wc -l | tr -d ' ')"
    echo ""
}

# ============================================================================
# Command: download
# ============================================================================
cmd_download() {
    # Delegate to download-snapshot.sh script
    "$SCRIPT_DIR/scripts/download-snapshot.sh" "$@"
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
    # Delegate to upload-snapshot.sh script
    "$SCRIPT_DIR/scripts/upload-snapshot.sh" "$@"
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
        cmd_list "$@"
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

