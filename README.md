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

## Downloading Snapshots

You can download a POKT snapshot from Stratos Storage at any time using the helper script:

```bash
./download-snapshot.sh <filename|latest>
```

Where:
- `latest` will fetch the most recent snapshot tarball available.
- `<filename>` is the exact tarball name you want to download.

This script will:
- Check your peer registration status
- Fetch the available file list
- Download the snapshot, with retries, to your current directory

Make sure `.env` is configured first (run `./init.sh` if not done already).


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

