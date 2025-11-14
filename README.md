# PokTSnap - SDS Node

A simple Docker-based setup for running a Stratos Decentralized Storage (SDS) node.

## Prerequisites

- Docker
- Docker Compose

## Setup

1. Copy the environment template and configure it:
   ```bash
   cp env.template .env
   ```

2. Edit `.env` file with your configuration:
   - `NETWORK_ADDRESS`: Your public IP address or hostname
   - `MNEMONIC_PHRASE`: Your 24-word mnemonic phrase
   - `NETWORK_PORT`: Network port (default: 18081)

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

