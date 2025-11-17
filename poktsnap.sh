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

