#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="poktsnap"
TAG="local"
LIST_MODE=false

# Check for --list flag
if [ "$1" = "--list" ] || [ "$1" = "-l" ]; then
    LIST_MODE=true
    DOWNLOAD_DIR="${2:-./downloads}"
    USE_PERSISTENT="${3:-false}"
else
    DOWNLOAD_DIR="${1:-./downloads}"
    USE_PERSISTENT="${2:-false}"
fi

# Show usage if --help is passed
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo -e "${GREEN}=== PokTSnap Build and Run ===${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS] [DOWNLOAD_DIR] [PERSISTENT]"
    echo ""
    echo "Options:"
    echo "  --list, -l      List available snapshot files without downloading"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "Arguments:"
    echo "  DOWNLOAD_DIR    Directory for downloaded files (default: ./downloads)"
    echo "  PERSISTENT      Use persistent volume for /sds (true/false, default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                          # Basic usage with ./downloads"
    echo "  $0 --list                   # List available snapshot files"
    echo "  $0 /path/to/downloads       # Custom download directory"
    echo "  $0 ./downloads true         # With persistent SDS volume (faster subsequent runs)"
    echo "  $0 --list ./downloads true  # List files with persistent volume"
    echo ""
    echo "Persistent mode benefits:"
    echo "  - Faster subsequent runs (reuses config/keys)"
    echo "  - Handles IP address changes automatically"
    echo "  - Named volume: poktsnap_sds_data"
    echo ""
    exit 0
fi

echo -e "${GREEN}=== PokTSnap Build and Run ===${NC}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker daemon is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

# Create downloads directory if it doesn't exist
if [ ! -d "$DOWNLOAD_DIR" ]; then
    echo -e "${YELLOW}Creating download directory: $DOWNLOAD_DIR${NC}"
    mkdir -p "$DOWNLOAD_DIR"
fi

echo -e "${GREEN}Step 1/2: Building Docker image...${NC}"
docker build -t ${IMAGE_NAME}:${TAG} .

echo ""
echo -e "${GREEN}Step 2/2: Running container...${NC}"
echo -e "Download directory: ${DOWNLOAD_DIR}"
echo -e "Image: ${IMAGE_NAME}:${TAG}"
echo -e "Persistent mode: ${USE_PERSISTENT}"
if [ "$LIST_MODE" = "true" ]; then
    echo -e "${BLUE}List mode: Will display available files${NC}"
fi
echo ""

# Build volume arguments based on mode
VOLUME_ARGS=()
if [ "$USE_PERSISTENT" = "true" ]; then
    echo -e "${BLUE}Using named volume 'poktsnap_sds_data' for /sds${NC}"
    echo -e "${BLUE}This will speed up subsequent runs and handle IP changes${NC}"
    VOLUME_ARGS+=(-v "poktsnap_sds_data:/sds")
fi
VOLUME_ARGS+=(-v "$(realpath "$DOWNLOAD_DIR"):/sds/download")

# Build environment arguments
ENV_ARGS=()
if [ "$LIST_MODE" = "true" ]; then
    ENV_ARGS+=(-e "DOWNLOAD_FILENAME=list")
fi

# Run the container
docker run --rm \
    -p 18081:18081 \
    "${VOLUME_ARGS[@]}" \
    "${ENV_ARGS[@]}" \
    ${IMAGE_NAME}:${TAG}

echo ""
echo -e "${GREEN}=== Done! ===${NC}"
echo -e "Downloaded files are in: $DOWNLOAD_DIR"
if [ "$USE_PERSISTENT" = "true" ]; then
    echo ""
    echo -e "${BLUE}Tip: Next run will be faster using the persistent volume!${NC}"
    echo -e "${BLUE}To remove the volume: docker volume rm poktsnap_sds_data${NC}"
fi
echo ""

