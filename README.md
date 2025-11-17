# PokTSnap - SDS Node

Download POKT snapshots from Stratos Decentralized Storage - quick and simple.

## Prerequisites

- Docker
- Docker Compose

## Quick Start

Run the initialization script:
```bash
./init.sh
```

This will:
- Check if Docker is installed
- Configure `.env` with your public IP and mnemonic phrase
- Start the node automatically

---

## Managing Snapshots

### Using the CLI Tool (Recommended)

The `poktsnap.sh` CLI provides a unified interface for all snapshot operations:

```bash
./poktsnap.sh <command> [args]
```

**Available Commands:**

```bash

./poktsnap.sh list                         # List all files in SDS storage
./poktsnap.sh download latest              # Download most recent snapshot
./poktsnap.sh download <filename>          # Download specific file
./poktsnap.sh upload /path/to/file.tar     # Upload a snapshot (file must exist inside container)
./poktsnap.sh delete <filehash>            # Delete a file from storage
./poktsnap.sh shell                        # Open interactive shell in container
```

## Terminal Commands

Open terminal: `./terminal.sh`

```bash
rp                                        # Register peer
list                                      # List files
wallets                                   # View wallets
get sdm://wallet-account/filehash         # Download file
prepay 85stos 6000000gwei --gas=6000000   # Prepay for storage
getoz <wallet-address>                    # Check ozone balance
put <file-path>                           # Upload file
ls                                        # List your files
sharefile <file-hash> 0 0                 # Share a file
allshare                                  # List all shared files
```

## Stopping the Node

```bash
docker compose down
```

## Data Storage

All node data is stored in the `./sds-data` directory.

