#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="ghcr.io/easy2stake/poktsnap-flash"
VERSION="${1:-v1.0.0}"  # Use first argument or default to v1.0.0
USERNAME="easy2stake"

echo -e "${GREEN}=== PokTSnap Flash Build and Push ===${NC}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker daemon is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

# Check for GitHub token
if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${YELLOW}GITHUB_TOKEN environment variable not set.${NC}"
    echo -e "${YELLOW}Please enter your GitHub Personal Access Token:${NC}"
    read -s GITHUB_TOKEN
    echo ""
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${RED}Error: GitHub token is required${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Step 1/4: Building Docker image...${NC}"
docker build -t ${IMAGE_NAME}:latest .

echo ""
echo -e "${GREEN}Step 2/4: Tagging image with version ${VERSION}...${NC}"
docker tag ${IMAGE_NAME}:latest ${IMAGE_NAME}:${VERSION}

echo ""
echo -e "${GREEN}Step 3/4: Logging in to GitHub Container Registry...${NC}"
echo "$GITHUB_TOKEN" | docker login ghcr.io -u ${USERNAME} --password-stdin

echo ""
echo -e "${GREEN}Step 4/4: Pushing images...${NC}"
docker push ${IMAGE_NAME}:latest
docker push ${IMAGE_NAME}:${VERSION}

echo ""
echo -e "${GREEN}=== Success! ===${NC}"
echo -e "Images pushed:"
echo -e "  - ${IMAGE_NAME}:latest"
echo -e "  - ${IMAGE_NAME}:${VERSION}"
echo ""
echo -e "To make the package public:"
echo -e "  1. Go to https://github.com/easy2stake?tab=packages"
echo -e "  2. Click on 'poktsnap-flash'"
echo -e "  3. Package settings → Change visibility to Public"
echo ""
echo -e "Usage example:"
echo -e "  docker run --rm -v ./downloads:/sds/download ${IMAGE_NAME}:latest"
echo ""

