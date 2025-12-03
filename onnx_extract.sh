#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="openpilot"

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --depth=1 --no-single-branch https://github.com/commaai/openpilot.git "$REPO_DIR"
fi

git -C "$REPO_DIR" fetch --depth=1 origin neurips-driving >/dev/null 2>&1 || true
git -C "$REPO_DIR" checkout -f FETCH_HEAD >/dev/null 2>&1 || true

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
