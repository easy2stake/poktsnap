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

## Usage

1. **Open terminal:** `./terminal.sh`
2. **Register peer:** `rp`
3. **List files:** `list`
4. **View wallets:** `wallets`
5. **Download file:** `get sdm://wallet-account/filehash`

## Using the Terminal

Once you've opened the terminal with `./terminal.sh`, you can use these commands:

### Prepay for Storage

Prepay for storage operations:

```bash
prepay 85stos 6000000gwei --gas=6000000
```

**Expected output:**

```
Request Accepted

>[INFO] 2025/11/04 00:03:54 prepay.go:28: Sending prepay message to SP! st1g0ljrfqp3d87hxtp5gx52lu0lh0le59475xz42
[INFO] 2025/11/04 00:03:54 prepay.go:49: get RspPrepay RES_SUCCESS 
[INFO] 2025/11/04 00:03:55 prepay.go:60: The prepay transaction was broadcast
```

### Check Ozone Balance

Check your ozone balance:

```bash
getoz st1g0ljrfqp3d87hxtp5gx52lu0lh0le59475xz42
```

### Upload a File

Upload a file to Stratos:

```bash
put /disk-storage/snaps/pocket/pocket-snap-data-20251104000201.tar.gz
```

**Expected output:**

```
Request Accepted

>[INFO] 2025/11/04 00:04:50 upload_slice.go:273: fileHash: v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo  uploaded：16.67 % 
[INFO] 2025/11/04 00:04:50 print.go:20: ################-----------------------------------------------------------------------------------
[INFO] 2025/11/04 00:04:50 upload_slice.go:273: fileHash: v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo  uploaded：33.33 % 
[INFO] 2025/11/04 00:04:50 print.go:20: #################################------------------------------------------------------------------
[INFO] 2025/11/04 00:04:51 upload_slice.go:273: fileHash: v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo  uploaded：50.00 % 
[INFO] 2025/11/04 00:04:51 print.go:20: ##################################################--------------------------------------------------
[INFO] 2025/11/04 00:04:52 upload_slice.go:273: fileHash: v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo  uploaded：66.67 % 
[INFO] 2025/11/04 00:04:52 print.go:20: ##################################################################---------------------------------
[INFO] 2025/11/04 00:04:53 upload_slice.go:273: fileHash: v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo  uploaded：83.33 % 
[INFO] 2025/11/04 00:04:53 print.go:20: ###################################################################################----------------
[INFO] 2025/11/04 00:04:53 upload_slice.go:273: fileHash: v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo  uploaded：100.00 % 
[INFO] 2025/11/04 00:04:53 print.go:20: ####################################################################################################
[INFO] 2025/11/04 00:04:59 upload_file.go:215: ******************************************************
[INFO] 2025/11/04 00:04:59 upload_file.go:217: * File  v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo
[INFO] 2025/11/04 00:04:59 upload_file.go:218: * has been sent to destinations
[INFO] 2025/11/04 00:04:59 upload_file.go:236: ******************************************************
```

### List Your Files

List all files you've uploaded:

```bash
ls
```

**Expected output:**

```
Request Accepted

>[INFO] 2025/11/04 00:05:26 find_file.go:73: _______________________________
[INFO] 2025/11/04 00:05:26 find_file.go:78: File name: passwords.secrets
[INFO] 2025/11/04 00:05:26 find_file.go:79: File hash: v05j1m567ebfkgmd7t8vk7j3cn3bqgplk6q050pg
[INFO] 2025/11/04 00:05:26 find_file.go:81: CreateTime : 1762202694
[INFO] 2025/11/04 00:05:26 find_file.go:73: _______________________________
[INFO] 2025/11/04 00:05:26 find_file.go:78: File name: pocket-snap-data-20251104000201.tar.gz
[INFO] 2025/11/04 00:05:26 find_file.go:79: File hash: v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo
[INFO] 2025/11/04 00:05:26 find_file.go:81: CreateTime : 1762207493
[INFO] 2025/11/04 00:05:26 find_file.go:90: ===============================
[INFO] 2025/11/04 00:05:26 find_file.go:91: Total: 2  Page: 0
```

### Share a File

Share a file using its hash:

```bash
sharefile v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo 0 0
```

**Expected output:**

```
Request Accepted

>[INFO] 2025/11/04 00:07:41 share.go:153: ShareId c89a72d115494965_a39c48dc57_943eec
[INFO] 2025/11/04 00:07:41 share.go:154: ShareLink sds://c89a72d115494965_a39c48dc57_943eec
[INFO] 2025/11/04 00:07:41 share.go:155: SharePassword 
```

### List All Shared Files

View all your shared files:

```bash
allshare
```

**Expected output:**

```
Request Accepted

>[INFO] 2025/11/04 00:08:24 share.go:100: _______________________________
[INFO] 2025/11/04 00:08:24 share.go:101: file_name: passwords.secrets
[INFO] 2025/11/04 00:08:24 share.go:102: file_hash: v05j1m567ebfkgmd7t8vk7j3cn3bqgplk6q050pg
[INFO] 2025/11/04 00:08:24 share.go:103: file_size: 20
[INFO] 2025/11/04 00:08:24 share.go:105: share_creation_time: 1762202794
[INFO] 2025/11/04 00:08:24 share.go:106: share_exp_time: 1777754794
[INFO] 2025/11/04 00:08:24 share.go:107: ShareId: 9fcea676e366474f_b4f9ce6670_e1324a
[INFO] 2025/11/04 00:08:24 share.go:108: ShareLink: sds://9fcea676e366474f_b4f9ce6670_e1324a
[INFO] 2025/11/04 00:08:24 share.go:100: _______________________________
[INFO] 2025/11/04 00:08:24 share.go:101: file_name: pocket-snap-data-20251104000201.tar.gz
[INFO] 2025/11/04 00:08:24 share.go:102: file_hash: v05j1m56iiuu71pb3o1gsdep0ce2r2l70bfbo7fo
[INFO] 2025/11/04 00:08:24 share.go:103: file_size: 188781431
[INFO] 2025/11/04 00:08:24 share.go:105: share_creation_time: 1762207659
[INFO] 2025/11/04 00:08:24 share.go:106: share_exp_time: 1777759659
[INFO] 2025/11/04 00:08:24 share.go:107: ShareId: c89a72d115494965_a39c48dc57_943eec
[INFO] 2025/11/04 00:08:24 share.go:108: ShareLink: sds://c89a72d115494965_a39c48dc57_943eec
```

## Stopping the Node

```bash
docker compose down
```

## Data Storage

All node data is stored in the `./sds-data` directory.

