#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="ghcr.io/easy2stake/poktsnap"
USERNAME="easy2stake"

# Show usage if --help is passed
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo -e "${GREEN}=== PokTSnap Build and Push ===${NC}"
    echo ""
    echo "Usage: $0 [VERSION]"
    echo ""
    echo "Arguments:"
    echo "  VERSION         Version tag for the Docker image (default: v1.0.0)"
    echo ""
    echo "Environment Variables:"
    echo "  SDS_VERSION    SDS repository version/branch to build (default: main)"
    echo "  GITHUB_TOKEN   GitHub Personal Access Token (will prompt if not set)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Build and push with default version v1.0.0"
    echo "  $0 v1.2.3            # Build and push with version v1.2.3"
    echo "  SDS_VERSION=v1.2.3 $0 v1.0.0  # Build with specific SDS version"
    echo ""
    echo "The script will:"
    echo "  1. Build Docker image with specified SDS_VERSION"
    echo "  2. Tag image as both 'latest' and the specified VERSION"
    echo "  3. Login to GitHub Container Registry (ghcr.io)"
    echo "  4. Push both tags to the registry"
    echo ""
    exit 0
fi

VERSION="${1:-v1.0.0}"  # Use first argument or default to v1.0.0
SDS_VERSION="${SDS_VERSION:-main}"  # Use environment variable or default to main

echo -e "${GREEN}=== PokTSnap Build and Push ===${NC}"
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
echo -e "SDS_VERSION: ${SDS_VERSION}"
docker build --build-arg SDS_VERSION=${SDS_VERSION} -t ${IMAGE_NAME}:latest .

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
echo -e "  2. Click on 'poktsnap'"
echo -e "  3. Package settings → Change visibility to Public"
echo ""
echo -e "Usage example:"
echo -e "  docker run --rm -v ./downloads:/sds/download ${IMAGE_NAME}:latest"
echo ""

