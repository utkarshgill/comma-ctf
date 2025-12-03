#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="openpilot"
BRANCH="neurips-driving"

# if repo is broken or incomplete, remove and reclone
if [ -d "$REPO_DIR" ] && [ ! -f "$REPO_DIR/selfdrive/modeld/models/driving_policy.onnx" ]; then
  echo "removing incomplete openpilot clone..."
  rm -rf "$REPO_DIR"
fi

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "cloning openpilot (branch: $BRANCH)..."
  git clone --depth=1 --branch="$BRANCH" https://github.com/commaai/openpilot.git "$REPO_DIR"
else
  echo "using existing openpilot clone"
  git -C "$REPO_DIR" fetch --depth=1 origin "$BRANCH" 2>&1 | grep -v "^remote:" || true
  git -C "$REPO_DIR" checkout -f FETCH_HEAD 2>&1 | head -n1 || true
fi

# extract and print the full clue text from ONNX
python3 - <<'PY'
import re

fn="openpilot/selfdrive/modeld/models/driving_policy.onnx"
b=open(fn,'rb').read()
i=b.find(b"ctf")
if i == -1:
    print("flag not found")
    raise SystemExit(1)

# extract a larger chunk to get the full clue including hex blob
chunk = b[i:i+2000].decode('utf-8','ignore')

# find where the hex blob ends (it's followed by binary garbage)
# print lines until we hit non-printable content
lines = chunk.split('\n')
for line in lines:
    # skip empty lines or lines that are mostly binary
    stripped = line.strip()
    if not stripped:
        continue
    # count printable chars
    printable = sum(1 for c in stripped if c.isprintable() or c in '\t')
    if len(stripped) > 0 and printable / len(stripped) > 0.9:
        # for hex blob lines, truncate if too long
        if re.match(r'^[0-9a-fA-F]{100,}$', stripped):
            print(stripped[:80] + "..." + stripped[-20:])
        else:
            print(stripped)
    else:
        # hit binary data, stop
        break
PY
