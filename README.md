# PokTSnap - SDS Node

A simple Docker-based setup for running a Stratos Decentralized Storage (SDS) node.

## Prerequisites

- Docker
- Docker Compose

## Setup

1. Run the initialization script:
   ```bash
   ./init.sh
   ```
   This will create `.env` and automatically set your public IP address.

2. Edit `.env` and add your `MNEMONIC_PHRASE` (24 words)

## Usage

1. **Start the node:** `docker compose up -d`
2. **Open terminal:** `./terminal.sh`
3. **Register peer:** `rp`
4. **List files:** `list`
5. **View wallets:** `wallets`
6. **Download file:** `get sdm://wallet-account/filehash`

## Stopping the Node

```bash
docker compose down
```

## Data Storage

All node data is stored in the `./sds-data` directory.

