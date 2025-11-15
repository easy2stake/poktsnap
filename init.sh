#!/bin/bash

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed!"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker Compose is available
if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not available!"
    echo "Please install Docker Compose first: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✓ Docker is installed"

# Copy env.template to .env
cp env.template .env

# Get public IP address
PUBLIC_IP=$(curl -4 -s ip.me)

# Get current user's UID and GID
USER_UID=$(id -u)
USER_GID=$(id -g)

# Replace placeholder with actual IP
sed -i.bak "s/your.public.ip.address/$PUBLIC_IP/" .env

# Replace UID and GID with actual values
sed -i.bak "s/SDS_UID=2048/SDS_UID=$USER_UID/" .env
sed -i.bak "s/SDS_GID=2048/SDS_GID=$USER_GID/" .env

rm .env.bak

echo "✓ Created .env file"
echo "✓ Set NETWORK_ADDRESS to: $PUBLIC_IP"
echo "✓ Set UID to: $USER_UID"
echo "✓ Set GID to: $USER_GID"
echo "✓ MNEMONIC_PHRASE already configured"
echo ""
echo "Starting the node..."
echo ""

# Start the node
docker compose up -d

echo ""
echo "=========================================="
echo "🚀 Node is starting!"
echo "=========================================="
echo ""
echo "Next step: Download a POKT snapshot"
echo ""
echo "./download-snapshot.sh latest"
echo ""
echo "To stop the node: docker compose down"
echo "=========================================="

