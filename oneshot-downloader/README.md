# PokTSnap Flash - One-Shot Snapshot Downloader

Self-contained Docker image for downloading POKT snapshots from Stratos Decentralized Storage.

## Features

- ✅ One-shot operation - downloads and exits cleanly
- ✅ Automatic peer registration
- ✅ Configurable via environment variables
- ✅ Download latest snapshot or specific file
- ✅ Retry logic for failed downloads
- ✅ No lingering containers (use with `--rm`)

## Usage

### Download Latest Snapshot

```bash
docker run --rm \
  -p 18081:18081 \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap:latest
```

The latest snapshot will be downloaded to `./downloads/` and the container will exit automatically.

### List Available Files

Before downloading, you can list all available snapshot files to see what's available:

```bash
docker run --rm \
  -p 18081:18081 \
  -e DOWNLOAD_FILENAME=list \
  ghcr.io/easy2stake/poktsnap:latest
```

### Download Specific File

```bash
docker run --rm \
  -p 18081:18081 \
  -e DOWNLOAD_FILENAME=pocket-snap-data-20251104000201.tar.gz \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap:latest
```

### Using Persistent Volumes (Faster Subsequent Runs)

For repeated downloads, use a named volume to persist the SDS configuration and keys. This significantly speeds up subsequent runs and automatically handles IP address changes:

```bash
docker run --rm \
  -p 18081:18081 \
  -v poktsnap_sds_data:/sds \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap:latest
```

**Benefits:**
- Faster subsequent runs (skips P2P key generation and account setup)
- Automatically updates network address when IP changes
- Configuration persists between runs

## Environment Variables

All environment variables are optional. The container works out-of-the-box with sensible defaults.

### Main Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DOWNLOAD_FILENAME` | `latest` | File to download. Use `latest` for most recent .tar file, `list` to display all available files, or specify exact filename like `pocket-snap-data-20251104000201.tar.gz` |
| `NETWORK_ADDRESS` | auto-detected | Your public IP address. Auto-detected via `ip.me` if not set |
| `NETWORK_PORT` | `18081` | P2P network port. Must match the exposed Docker port |

### Advanced Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `WALLET_ADDRESS` | `st1g0ljrfqp3d87hxtp5gx52lu0lh0le59475xz42` | Stratos wallet address for SDM URLs |
| `MNEMONIC_PHRASE` | (test phrase) | 24-word mnemonic phrase for wallet |
| `RPC_URL` | `http://127.0.0.1:18281` | Internal RPC endpoint |
| `RPC_PASSWORD` | (empty) | Password for RPC client |
| `RPC_NAMESPACES` | `user,owner` | RPC namespaces to enable |
| `DEBUG` | `false` | Set to `true` to show ppd process output for debugging |

### Build-time Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SDS_VERSION` | `main` | SDS version/branch to build from GitHub |
| `RUN_AS_USER` | `sds` | User to run the process as |
| `WORK_DIR` | `/sds` | Working directory inside container |

### Using Environment File

Create a `.env` file (see `env.template` for reference):

```bash
cp env.template .env
# Edit .env with your values
```

Run with environment file:

```bash
docker run --rm \
  -p 18081:18081 \
  --env-file .env \
  -v ./downloads:/sds/download \
  ghcr.io/easy2stake/poktsnap:latest
```

## How It Works

1. Container starts and initializes SDS node
2. Auto-detects public IP (or uses provided `NETWORK_ADDRESS`)
3. Registers peer with Stratos network
4. Fetches file list from network
5. Identifies target file (latest or specific name)
6. Downloads file with automatic retry (up to 5 attempts)
7. Saves to `/sds/download/` (mounted volume)
8. Shuts down and exits

## Requirements

- **Port mapping**: `-p 18081:18081` (or custom port with `NETWORK_PORT`)
- **Volume mount**: `-v ./downloads:/sds/download` (to persist downloaded files)
- **Internet access**: For IP auto-detection and Stratos network connectivity

## Troubleshooting

### Container exits immediately
- Check if IP auto-detection failed (requires internet access to `ip.me`)
- Verify `NETWORK_ADDRESS` is accessible from the internet
- Check logs: `docker logs <container-id>`

### Download fails with code -5
- Network connectivity issues
- The script automatically retries up to 5 times

### Permission issues with download folder
- Container runs as user ID 2048 by default
- Ensure the mount point has write permissions

## License

MIT

## Links

- [Stratos Network](https://www.thestratos.org/)
- [SDS Documentation](https://docs.thestratos.org/)

