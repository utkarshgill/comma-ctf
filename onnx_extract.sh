#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="openpilot"

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --depth=1 --no-single-branch https://github.com/commaai/openpilot.git "$REPO_DIR"
fi

git -C "$REPO_DIR" fetch --depth=1 origin neurips-driving
git -C "$REPO_DIR" checkout -f FETCH_HEAD

# find readable strings and the flag
strings -a "$REPO_DIR/selfdrive/modeld/models/driving_policy.onnx" | grep -ni -E "ctf|flag\{" || true

# show context around the match
python3 - <<'PY'
fn="openpilot/selfdrive/modeld/models/driving_policy.onnx"
b=open(fn,'rb').read()
i=b.find(b"ctf")
print(b[max(0,i-500):i+500].decode('utf-8','ignore'))
PY
