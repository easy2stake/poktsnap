┌─────────────────────────────────────────────────────────────────┐
│ MONITOR-AND-UPLOAD WORKFLOW (MAX_FILE_SIZE = 10GB)             │
└─────────────────────────────────────────────────────────────────┘

START:
│
├─ Load RPC utilities (logging, validation functions)
├─ Validate RPC_URL is set
│
├─ SET: MAX_FILE_SIZE_GB = 10
├─ SET: MAX_FILE_SIZE_BYTES = 10,737,418,240 (10GB in bytes)
├─ SET: ARCHIVE_DIR = "/archive"
│
├─ CHECK: Does /archive exist?
│   └─ NO → EXIT ERROR
│
├─ FETCH: Get list of ALL files already uploaded to Stratos
│   └─ UPLOADED_FILES = [filename1, filename2, ...]
│
└─ SCAN: Find all *.tar, *.tar.gz, *.tar.zstd files in /archive
    └─ WHERE: File age > 15 minutes
    └─ FOR EACH FILE found:
        │
        ├─ LOG: "Found file: FILENAME"
        │
        ├─ DECISION: Is FILENAME already in UPLOADED_FILES?
        │   ├─ YES → LOG: "SKIP: already uploaded"
        │   │       └─ CONTINUE to next file
        │   │
        │   └─ NO → PROCEED:
        │       │
        │       ├─ GET: FILE_SIZE (in bytes)
        │       │
        │       └─ DECISION: FILE_SIZE >= 10GB?
        │           │
        │           ├─────────────────────────────────────────────────────
        │           │ YES: FILE >= 10GB (LARGE FILE - SPLIT & UPLOAD)    │
        │           ├─────────────────────────────────────────────────────
        │           │   │
        │           │   ├─ LOG: "File is large (XXgb >= 10GB)"
        │           │   │
        │           │   ├─ CREATE: /archive/tmp/ directory
        │           │   │
        │           │   ├─ CHECK: Do chunks exist in /archive/tmp/?
        │           │   │   └─ Pattern: FILENAME.partaa, FILENAME.partab, etc.
        │           │   │
        │           │   ├─ DECISION: Chunks exist?
        │           │   │   │
        │           │   │   ├─ YES → LOG: "Using existing chunks"
        │           │   │   │       └─ CHUNK_FILES = existing chunks
        │           │   │   │
        │           │   │   └─ NO → LOG: "Splitting file into chunks..."
        │           │   │           ├─ EXECUTE: split -b 10GB /archive/FILENAME /archive/tmp/FILENAME.part
        │           │   │           │   └─ Creates: FILENAME.partaa, partab, partac, ...
        │           │   │           │
        │           │   │           ├─ SUCCESS?
        │           │   │           │   ├─ YES → CHUNK_FILES = new chunks
        │           │   │           │   └─ NO → LOG ERROR, CONTINUE to next file
        │           │   │
        │           │   ├─ COUNT: CHUNK_COUNT = number of chunks
        │           │   │
        │           │   ├─ LOG: "Found X chunk(s), checking upload status..."
        │           │   │
        │           │   ├─ FOR EACH CHUNK in CHUNK_FILES:
        │           │   │   │
        │           │   │   ├─ GET: CHUNK_NAME (e.g., FILENAME.partaa)
        │           │   │   │
        │           │   │   ├─ DECISION: Is CHUNK_NAME in UPLOADED_FILES?
        │           │   │   │   │
        │           │   │   │   ├─ YES → LOG: "SKIP: chunk already uploaded"
        │           │   │   │   │       ├─ GET: CHUNK_HASH from UPLOADED_FILES
        │           │   │   │   │       └─ ADD to MANIFEST_CONTENT: {filename, hash}
        │           │   │   │   │
        │           │   │   │   └─ NO → LOG: "Uploading chunk X/Y: CHUNK_NAME"
        │           │   │   │           ├─ UPLOAD: chunk to Stratos via rpcclient
        │           │   │   │           │
        │           │   │   │           └─ DECISION: Upload successful?
        │           │   │   │               │
        │           │   │   │               ├─ YES → LOG: "SUCCESS"
        │           │   │   │               │       ├─ GET: CHUNK_HASH from response
        │           │   │   │               │       └─ ADD to MANIFEST_CONTENT: {filename, hash}
        │           │   │   │               │
        │           │   │   │               └─ NO → LOG: "ERROR: Failed"
        │           │   │   │                       ├─ SET: UPLOAD_SUCCESS = false
        │           │   │   │                       └─ BREAK chunk loop
        │           │   │
        │           │   ├─ DECISION: All chunks uploaded? (UPLOAD_SUCCESS = true)
        │           │   │   │
        │           │   │   ├─ YES → CREATE MANIFEST:
        │           │   │   │       │
        │           │   │   │       ├─ CREATE FILE: /archive/tmp/FILENAME.manifest
        │           │   │   │       │   └─ Content:
        │           │   │   │       │       {
        │           │   │   │       │         "original_filename": "FILENAME",
        │           │   │   │       │         "original_size": FILE_SIZE,
        │           │   │   │       │         "chunk_count": CHUNK_COUNT,
        │           │   │   │       │         "chunk_size": 10737418240,
        │           │   │   │       │         "chunks": [
        │           │   │   │       │           {"filename": "partaa", "hash": "abc123"},
        │           │   │   │       │           {"filename": "partab", "hash": "def456"}
        │           │   │   │       │         ]
        │           │   │   │       │       }
        │           │   │   │       │
        │           │   │   │       ├─ UPLOAD: manifest to Stratos
        │           │   │   │       │
        │           │   │   │       └─ DECISION: Manifest upload successful?
        │           │   │   │           │
        │           │   │   │           ├─ YES → LOG: "SUCCESS: All chunks + manifest uploaded"
        │           │   │   │           │       ├─ CLEANUP: rm /archive/tmp/FILENAME.part*
        │           │   │   │           │       ├─ CLEANUP: rm /archive/tmp/FILENAME.manifest
        │           │   │   │           │       └─ KEEP: /archive/tmp/ directory
        │           │   │   │           │       └─ KEEP: /archive/FILENAME (original file)
        │           │   │   │           │
        │           │   │   │           └─ NO → LOG: "ERROR: Failed to upload manifest"
        │           │   │   │                   ├─ CLEANUP: rm chunks + manifest
        │           │   │   │                   └─ KEEP: /archive/FILENAME (original file)
        │           │   │   │
        │           │   │   └─ NO → LOG: "ERROR: Failed to upload all chunks"
        │           │   │           ├─ CLEANUP: rm /archive/tmp/FILENAME.part*
        │           │   │           └─ KEEP: /archive/FILENAME (original file)
        │           │   │
        │           │   └─ CONTINUE to next file
        │           │
        │           ├─────────────────────────────────────────────────────
        │           │ NO: FILE < 10GB (SMALL FILE - DIRECT UPLOAD)       │
        │           ├─────────────────────────────────────────────────────
        │           │   │
        │           │   ├─ LOG: "Uploading: FILENAME"
        │           │   │
        │           │   ├─ UPLOAD: /archive/FILENAME to Stratos via rpcclient
        │           │   │
        │           │   └─ DECISION: Upload successful?
        │           │       │
        │           │       ├─ YES → LOG: "SUCCESS: uploaded successfully"
        │           │       │       └─ LOG: "File hash: HASH"
        │           │       │
        │           │       └─ NO → LOG: "ERROR: Upload failed"
        │           │               └─ LOG: Error output
        │           │
        │           └─ CONTINUE to next file

END: "Snapshot upload monitor completed"


┌─────────────────────────────────────────────────────────────────┐
│ FILE STATES ON DISK AFTER SUCCESSFUL UPLOAD                    │
└─────────────────────────────────────────────────────────────────┘

Small File (< 10GB):
  /archive/
    └── snapshot.tar                 ← Original (kept)

Large File (>= 10GB):
  /archive/
    ├── snapshot.tar                 ← Original (kept)
    └── tmp/                         ← Directory (kept, empty)

On Stratos (Small File):
  → snapshot.tar (uploaded)

On Stratos (Large File):
  → snapshot.tar.partaa (uploaded)
  → snapshot.tar.partab (uploaded)
  → snapshot.tar.partac (uploaded)
  → snapshot.tar.manifest (uploaded)


┌─────────────────────────────────────────────────────────────────┐
│ EXAMPLE: 25GB File Upload                                       │
└─────────────────────────────────────────────────────────────────┘

1. Find: /archive/snapshot-25gb.tar (age > 15 min)
2. Check: Not in UPLOADED_FILES → proceed
3. Size: 25GB >= 10GB → split mode
4. Check: /archive/tmp/snapshot-25gb.tar.part* exists?
   └─ No → Split into 3 chunks (10GB + 10GB + 5GB)
       ├─ snapshot-25gb.tar.partaa (10GB)
       ├─ snapshot-25gb.tar.partab (10GB)
       └─ snapshot-25gb.tar.partac (5GB)
5. Upload chunks:
   ├─ partaa not uploaded → upload → hash: abc123
   ├─ partab not uploaded → upload → hash: def456
   └─ partac not uploaded → upload → hash: ghi789
6. Create manifest with all chunk hashes
7. Upload manifest → hash: xyz999
8. Cleanup: Delete chunks + manifest from /archive/tmp/
9. Keep: Original /archive/snapshot-25gb.tar