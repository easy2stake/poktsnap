# PokTSnap Flash - One-Shot Snapshot Downloader

Self-contained Docker image for downloading POKT snapshots from Stratos Decentralized Storage.

## Features

- ✅ One-shot operation - downloads and exits cleanly
- ✅ Automatic peer registration
- ✅ Configurable via environment variables
- ✅ Download latest snapshot or specific file
- ✅ Retry logic for failed downloads
- ✅ No lingering containers (use with `--rm`)

## Quick Start

### Download Latest Snapshot

Simplest usage (all defaults):

```bash
docker run --rm \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap-flash:latest
```

With custom wallet address:

```bash
docker run --rm \
  -e WALLET_ADDRESS=st1yourwalletaddress \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap-flash:latest
```

With fully custom configuration:

```bash
docker run --rm \
  -e NETWORK_ADDRESS=your.ip.address \
  -e MNEMONIC_PHRASE="your 24 word mnemonic phrase" \
  -e WALLET_ADDRESS=st1yourwalletaddress \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap-flash:latest
```

The snapshot will be downloaded to `./downloads/` and the container will exit automatically.

## Environment Variables

### All Optional with Defaults

- **NETWORK_ADDRESS** - Your public IP address (auto-detected via `ip.me` if not set)
- **MNEMONIC_PHRASE** - Your 24-word mnemonic phrase (uses default test phrase if not set)
- **WALLET_ADDRESS** - Stratos wallet address for SDM URLs (default: `st1g0ljrfqp3d87hxtp5gx52lu0lh0le59475xz42`)

### Optional

- **DOWNLOAD_FILENAME** - File to download (default: `latest`)
  - `latest` - Downloads the most recent .tar file
  - Specific filename - e.g., `pocket-snap-data-20251104000201.tar.gz`
- **NETWORK_PORT** - Network port (default: `18081`)
- **RPC_NAMESPACES** - RPC namespaces (default: `user,owner`)
- **RPC_PASSWORD** - RPC password (default: empty)
- **RPC_URL** - RPC URL (default: `http://127.0.0.1:18281`)
- **SDS_VERSION** - SDS version/branch to build (default: `main`)

## Usage Examples

### Download Specific File

```bash
docker run --rm \
  -e DOWNLOAD_FILENAME=pocket-snap-data-20251104000201.tar.gz \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap-flash:latest
```

### Use Custom Port

```bash
docker run --rm \
  -e NETWORK_PORT=18082 \
  -p 18082:18082 \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap-flash:latest
```

### Using env.template

1. Copy the template:
```bash
cp env.template .env
```

2. Edit `.env` with your values

3. Run with env file:
```bash
docker run --rm \
  --env-file .env \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap-flash:latest
```

## How It Works

1. Container starts and initializes SDS node
2. Waits 5 seconds for node to be ready
3. Registers peer (or confirms already registered)
4. Fetches file list from Stratos network
5. Identifies target file (latest or specific name)
6. Downloads file with automatic retry (up to 5 attempts)
7. Saves to `/sds/download/` (mounted volume)
8. Shuts down node cleanly
9. Container exits

## Volume Mounting

The download directory must be mounted to persist files:

```bash
-v ./downloads:/sds/download
```

Downloaded files appear in `./downloads/` on your host.

## Troubleshooting

### Container exits immediately
- Check if IP auto-detection failed (requires internet access to ip.me)
- Verify custom WALLET_ADDRESS if provided
- Check logs: `docker logs container-name`

### Download fails with code -5
- Node may not be fully ready - increase wait time in entrypoint.sh
- Network connectivity issues
- The script automatically retries up to 5 times

### Permission issues with download folder
- Ensure the mount point has correct permissions
- Container runs as user ID 2048 by default
- Override with: `-e SDS_UID=$(id -u) -e SDS_GID=$(id -g)`

## License

MIT

## Links

- [Stratos Network](https://www.thestratos.org/)
- [SDS Documentation](https://docs.thestratos.org/)

