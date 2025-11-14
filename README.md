# PokTSnap - SDS Node

A simple Docker-based setup for running a Stratos Decentralized Storage (SDS) node.

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

## Usage

1. **Open terminal:** `./terminal.sh`
2. **Register peer:** `rp`
3. **List files:** `list`
4. **View wallets:** `wallets`
5. **Download file:** `get sdm://wallet-account/filehash`

## Stopping the Node

```bash
docker compose down
```

## Data Storage

All node data is stored in the `./sds-data` directory.

