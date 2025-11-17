#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="poktsnap"
TAG="local"
DOWNLOAD_DIR="${1:-./downloads}"  # Use first argument or default to ./downloads

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
echo ""

# Run the container
docker run --rm \
    -p 18081:18081 \
    -v "$(realpath "$DOWNLOAD_DIR"):/sds/download" \
    ${IMAGE_NAME}:${TAG}

echo ""
echo -e "${GREEN}=== Done! ===${NC}"
echo -e "Downloaded files are in: $DOWNLOAD_DIR"
echo ""

