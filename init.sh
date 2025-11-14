#!/bin/bash

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
echo "Next steps:"
echo "1. docker compose up -d          (start the node)"
echo "2. ./terminal.sh                 (open terminal)"
echo "3. rp                            (register peer)"
echo "4. list                          (list available files)"
echo "5. wallets                       (view wallet accounts)"
echo "6. get sdm://wallet/filehash     (download files)"

