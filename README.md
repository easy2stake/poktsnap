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

### 1. Start the Node

```bash
docker compose up -d
```

### 2. Open the Terminal

```bash
./terminal.sh
```

### 3. Register the Peer

In the terminal, run:
```
rp
```

### 4. List Available Files

```
list
```

### 5. View Wallet Accounts

To list the wallet account used to download files:
```
wallets
```

### 6. Download Files

To download a file:
```
get sdm://wallet-account/filehash
```

Replace `wallet-account` with your wallet address and `filehash` with the file's hash.

## Stopping the Node

```bash
docker compose down
```

## Data Storage

All node data is stored in the `./sds-data` directory.

