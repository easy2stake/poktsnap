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

# Replace placeholder with actual IP
sed -i.bak "s/your.public.ip.address/$PUBLIC_IP/" .env
rm .env.bak

echo "✓ Created .env file"
echo "✓ Set NETWORK_ADDRESS to: $PUBLIC_IP"
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
echo "Next steps:"
echo "1. ./terminal.sh                 (open terminal)"
echo "2. rp                            (register peer)"
echo "3. list                          (list available files)"
echo "4. wallets                       (view wallet accounts)"
echo "5. get sdm://wallet/filehash     (download files)"
echo ""
echo "To stop the node: docker compose down"
echo "=========================================="

