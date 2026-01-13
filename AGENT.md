# AGENT.md - Project Knowledge Base

This document provides context and guidelines for AI agents working on this project.

## Project Overview

**PokTSnap** is a Docker-based system for uploading and downloading POKT (Pocket Network) snapshots to/from Stratos Decentralized Storage (SDS). The project supports automatic chunking of large files (>10GB) and provides both interactive CLI tools and automated cron-based uploading.

## Key Architecture Components

### 1. Main Scripts

- **`poktsnap.sh`** - Main CLI interface for all operations
- **`init.sh`** - Initial setup script (creates .env, configures Docker)
- **`entrypoint.sh`** - Container entrypoint that runs ppd and sets up cron jobs

### 2. Upload Scripts

- **`scripts/monitor-and-upload.sh`** - Automated cron-based uploader (runs every 10 minutes)
- **`scripts/upload-snapshot.sh`** - Manual upload script (called via `poktsnap.sh upload`)
- **Location**: Scripts run inside Docker container via `docker exec`

### 3. Download Scripts

- **`scripts/download-snapshot.sh`** - Downloads files with automatic chunk reassembly

### 4. Utility Scripts

- **`scripts/cleanup-old-snapshots.sh`** - Manages retention policies (cron hourly)
- **`scripts/rpc-utils.sh`** - Shared RPC utilities (logging, validation, file listing)

### 5. Oneshot Downloader

- **`oneshot-downloader/`** - Self-contained Docker image for one-time downloads
- Separate from main node, used for downloading snapshots without running persistent node

## Critical Design Decisions

### File Splitting Logic

**Threshold**: Files >= 10GB are automatically split into chunks
- Configurable via `MAX_FILE_SIZE_GB` variable
- User changed from 50GB to 10GB during development
- Location: `scripts/monitor-and-upload.sh` line 21

**Chunk Storage**:
- Original file: `/archive/snapshot.tar` (always kept)
- Chunks: `/archive/tmp/snapshot.tar.partaa`, `.partab`, etc.
- Manifest: `/archive/tmp/snapshot.tar.manifest` (JSON metadata)
- **tmp directory persists** after upload (only files inside are deleted)

**Orphaned Chunk Handling**:
- If original file is deleted from `/archive` but chunks remain in `/tmp`
- **CRITICAL**: Only processes orphaned chunks if local manifest exists
- Manifest proves the split was complete - without it, chunks may be incomplete
- **Validates chunk count**: Actual chunks must match manifest's `chunk_count`
- If chunks are missing → skip with error (manual intervention required)
- Calculates `original_size` from sum of all chunk sizes
- **Separate cleanup process** handles removing old chunks from `/tmp`
- This allows crash recovery even if original file was deleted

**Upload Behavior**:
1. Check if file >= 10GB
2. Check if chunks exist in `/tmp` → reuse if found
3. **Create local manifest immediately** (proof of split, hashes null)
4. Check if each chunk already uploaded → skip if uploaded
5. Upload remaining chunks (collect hashes)
6. **On failure**: Keep chunks AND manifest for retry on next run
7. **On success**: Update manifest with hashes, mark `upload_complete: true`
8. Upload manifest to Stratos
9. Delete chunks and manifest files (keep `/tmp` directory)
10. Keep original file in `/archive`

### Manifest File Format

**Manifest Lifecycle**: Created immediately after split, updated after upload

**Initial Manifest** (after split, before upload):
```json
{
  "original_filename": "snapshot.tar",
  "original_size": 53687091200,
  "chunk_count": 3,
  "chunk_size": 10737418240,
  "split_complete": true,
  "upload_complete": false,
  "chunks": [
    {"filename": "snapshot.tar.partaa", "hash": null},
    {"filename": "snapshot.tar.partab", "hash": null},
    {"filename": "snapshot.tar.partac", "hash": null}
  ]
}
```

**Final Manifest** (after upload completion):
```json
{
  "original_filename": "snapshot.tar",
  "original_size": 53687091200,
  "chunk_count": 3,
  "chunk_size": 10737418240,
  "split_complete": true,
  "upload_complete": true,
  "chunks": [
    {"filename": "snapshot.tar.partaa", "hash": "v05ahm51f8pd..."},
    {"filename": "snapshot.tar.partab", "hash": "v05ahm51f8pd..."},
    {"filename": "snapshot.tar.partac", "hash": "v05ahm51f8pd..."}
  ]
}
```

**Orphaned Chunk Manifest** (includes `orphaned: true` flag):
```json
{
  "original_filename": "snapshot.tar",
  "original_size": 53687091200,
  "chunk_count": 3,
  "chunk_size": 10737418240,
  "split_complete": true,
  "upload_complete": true,
  "orphaned": true,
  "chunks": [...]
}
```

**Purpose**:
- **Proof of Split**: Manifest exists locally even if original file deleted
- **Upload Tracking**: `upload_complete` flag shows if all chunks uploaded
- **Reassembly**: Download script uses manifest to reconstruct file
- **Integrity**: Original size used for verification after reassembly

### Download and Reassembly

**Smart Detection**:
- Script checks if `filename.manifest` exists
- If manifest exists → download chunks and reassemble
- If no manifest → download file directly

**Process**:
1. Download manifest
2. Parse JSON to get chunk list
3. Download each chunk (skip if exists locally)
4. Concatenate chunks: `cat partaa partab partac > snapshot.tar`
5. Verify file size matches `original_size`
6. Clean up chunks and manifest

### Path Conventions

**Inside Container**:
- Working directory: `/sds`
- Download directory: `/sds/download`
- Config: `/sds/config`

**On Host**:
- Mounted volume: `./sds-data` → `/sds`
- Downloaded files: `./sds-data/download/`
- Archive directory: Set via `ARCHIVE_DIR` env var (default: `/archive`)

**Script Execution**:
- Upload scripts run **inside container** (via cron or `docker exec`)
- Download scripts run **on host** and use `docker exec` to call container commands

## Important Behaviors

### Concurrent Execution Prevention

**Lock Mechanism** (monitor-and-upload.sh):
- Lockfile: `/tmp/monitor-and-upload.lock`
- Prevents concurrent cron executions from racing
- Detects and removes stale locks if process died
- Auto-cleanup via `trap` on exit

```bash
# If cron triggers while upload in progress:
# - New instance checks lockfile
# - Finds running PID → exits gracefully
# - Logs: "Another instance is already running"
# - No duplicate uploads or race conditions
```

**Why This Matters**:
- Large files (>10GB) can take 10+ minutes to upload chunks
- Cron runs every 10 minutes → overlap is likely
- Without lock: file corruption, duplicate uploads, manifest conflicts

### File Existence Checks

**Always check inside container**:
```bash
# CORRECT
docker exec -u sds sds-node test -f "$FILEPATH"

# WRONG
[ -f "$FILEPATH" ]  # This checks host filesystem
```

### Upload Workflow (monitor-and-upload.sh)

```
START (cron every 10 minutes)
  ↓
Check lockfile (/tmp/monitor-and-upload.lock)
  ├─ Lockfile exists & process running? → Exit gracefully
  └─ No lock or stale lock? → Continue
  ↓
Create lockfile with current PID
  ↓
Scan /archive for files (*.tar, *.tar.gz, *.tar.zstd)
  ↓ (age > 15 minutes)
  ↓
For each file:
  ├─ Already uploaded? → Skip
  ├─ Size < 10GB? → Upload directly
  └─ Size >= 10GB?
      ├─ Chunks exist in /tmp? → Use existing
      ├─ No chunks? → Split file
      ├─ For each chunk:
      │   ├─ Already uploaded? → Skip, use hash
      │   └─ Not uploaded? → Upload chunk
      ├─ Create manifest JSON
      ├─ Upload manifest
      └─ Cleanup: rm chunks + manifest (keep /tmp dir)
  ↓
Scan /archive/tmp for orphaned chunks
  ↓
For each set of orphaned chunks:
  ├─ Original file exists in /archive? → Skip (already processed above)
  ├─ Manifest exists on Stratos? → Skip (already completed)
  ├─ NO local manifest? → Skip (split may be incomplete!)
  ├─ Chunk count mismatch? → Skip (chunks missing/corrupted!)
  └─ All checks passed?
      ├─ Calculate total size from chunks
      ├─ For each chunk:
      │   ├─ Already uploaded? → Skip, use hash
      │   └─ Not uploaded? → Upload chunk
      ├─ Update manifest with hashes
      ├─ Upload manifest
      └─ Cleanup: rm chunks + manifest (keep /tmp dir)
```

### List Command Flags

- `./poktsnap.sh list` - Shows only .tar files (default)
- `./poktsnap.sh list -a` or `--all` - Shows ALL files (chunks, manifests, etc.)

## Docker Configuration

### Main Deployment

- **docker-compose.yml** - Basic SDS node
- **docker-compose-put.yml** - Node with cron jobs for auto-upload/cleanup
- Mounts: `./sds-data:/sds`, `${ARCHIVE_DIR}:/archive`

### Build Arguments

- **SDS_VERSION** - Git branch/tag to build from (default: `main`)
- Usage: `SDS_VERSION=v1.2.3 ./oneshot-downloader/build-and-run.sh`

## Code Conventions

### Function Organization

**Always use functions for clarity** (especially in complex scripts):
```bash
# Good - Clear function-based structure
download_file() { ... }
check_for_manifest() { ... }
download_chunks() { ... }
reassemble_chunks() { ... }

# Usage in main logic
if check_for_manifest "$FILENAME"; then
    download_chunks "$FILENAME"
    reassemble_chunks "$FILENAME"
fi
```

### Logging in Cron Scripts

Use shared `log()` function from `rpc-utils.sh`:
```bash
log "$SCRIPT_NAME" "message"
# Output: [script-name] [2026-01-13 10:30:00] message
```

### Error Handling

- Use `set -e` in build scripts to exit on error
- In cron scripts, log errors but continue to next file
- Always cleanup temporary files on failure

## Common Tasks

### Adding a New Upload Feature

1. Modify `scripts/monitor-and-upload.sh` for automated uploads
2. Modify `scripts/upload-snapshot.sh` for manual uploads
3. Test both paths
4. Update help text in `poktsnap.sh` if needed

### Adding a New Download Feature

1. Add function to `scripts/download-snapshot.sh`
2. Keep function-based structure
3. Handle both regular files and chunked files
4. Test with both file types

### Changing File Size Threshold

1. Update `MAX_FILE_SIZE_GB` in `scripts/monitor-and-upload.sh`
2. Update corresponding variable in `scripts/upload-snapshot.sh`
3. Update comments that reference the size (e.g., line 22)

### Adding Environment Variables

1. Add to `env.template` with documentation
2. Update `entrypoint.sh` if needed by cron jobs
3. Document in README.md

## Testing Considerations

### Manual Testing Workflow

```bash
# 1. Initialize
./init.sh

# 2. List files
./poktsnap.sh list
./poktsnap.sh list --all

# 3. Upload small file (< 10GB)
./poktsnap.sh upload /sds/snapshot-5gb.tar

# 4. Upload large file (>= 10GB) - should split
./poktsnap.sh upload /sds/snapshot-25gb.tar

# 5. Download regular file
./poktsnap.sh download snapshot-5gb.tar

# 6. Download chunked file (should reassemble)
./poktsnap.sh download snapshot-25gb.tar

# 7. Verify auto-upload (wait 10 minutes)
docker logs sds-node | grep monitor-and-upload
```

## Troubleshooting

### Cron Jobs Not Running

1. Check if scripts are mounted:
   ```bash
   docker exec sds-node ls -la /usr/local/bin/ | grep -E "(monitor|cleanup)"
   ```

2. Check crontab:
   ```bash
   docker exec -u sds sds-node crontab -l
   ```

3. Check cron logs:
   ```bash
   docker logs sds-node | grep -i cron
   ```

### Chunks Not Being Reused

- Check if `/archive/tmp/` directory exists
- Check if chunk files match pattern: `filename.partaa`, `filename.partab`
- Check permissions on tmp directory

### Download Reassembly Fails

- Verify manifest JSON is valid
- Check all chunks downloaded: `ls -lh ./sds-data/download/*.part*`
- Check file size verification output
- Ensure sufficient disk space

## Key Files to Never Modify

1. **Original files in `/archive`** - These are source files, never delete
2. **`/sds/config`** - Contains node keys and configuration
3. **`.env`** - Contains sensitive credentials (already gitignored)

## Version Control

### What's Ignored (.gitignore)

- `sds-data/` - Container data
- `.env` - Credentials
- `downloads/` - Downloaded snapshots

### What's Tracked

- All scripts
- Dockerfiles
- `env.template` - Template for .env
- Documentation

## Future Enhancements to Consider

1. **Parallel chunk downloads** - Currently sequential
2. **Resume interrupted downloads** - Partially implemented (skips existing chunks)
3. **Compression of chunks** - Before upload
4. **Integrity verification** - Hash checking for chunks
5. **Progress bars** - For long uploads/downloads
6. **Notification system** - Alert on upload/download completion
7. **Web UI** - For monitoring and management

## Important Notes

- **File paths in scripts**: Always use container paths when calling rpcclient
- **Streaming output**: Upload scripts use `tee /dev/tty` to show progress
- **Debug mode**: Set `DEBUG=true` in oneshot-downloader for verbose output
- **Chunk naming**: Uses `split` default naming (partaa, partab, etc.)
- **Manifest is critical**: Without it, chunks cannot be reassembled

## Contact and Documentation

- Main README: `/README.md`
- Oneshot downloader: `/oneshot-downloader/README.md`
- Upload workflow diagram: `/scripts/monitor-and-upload.md`

---

*Last Updated: Based on conversation 2026-01-13*
*This document should be updated when significant architectural changes are made.*
