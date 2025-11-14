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
echo ""
echo "Next steps:"
echo "1. Edit .env and add your MNEMONIC_PHRASE"
echo "2. docker compose up -d          (start the node)"
echo "3. ./terminal.sh                 (open terminal)"
echo "4. rp                            (register peer)"
echo "5. list                          (list available files)"
echo "6. wallets                       (view wallet accounts)"
echo "7. get sdm://wallet/filehash     (download files)"

