#!/usr/bin/env bash
set -euo pipefail

VENV_DIR="${VENV_DIR:-.venv}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if [ ! -d "$VENV_DIR" ]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"

PYTHON="$VENV_DIR/bin/python"
pip install --upgrade pip >/dev/null 2>&1
pip install --upgrade jpegio numpy pycryptodome >/dev/null 2>&1

if ! command -v exiftool >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y libimage-exiftool-perl
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y perl-Image-ExifTool
  elif command -v brew >/dev/null 2>&1; then
    brew install exiftool
  fi
fi

OUT=found_flags.txt
: > "$OUT"

run_and_extract(){
  label="$1"
  cmd="$2"
  slug=$(echo "$label" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '_')
  log_file=$(mktemp "/tmp/run_${slug}_XXXXXX")

  echo "════════════════════════════════════════════════════════════════════"
  echo "Stage: $label"
  echo "Command: $cmd"
  echo "────────────────────────────────────────────────────────────────────"

  if bash -c "$cmd" > "$log_file" 2>&1; then
    status="✓ success"
  else
    status="✗ failed"
  fi
  echo "Status: $status"

  # Extract flags from log
  matches=$(grep -aoE 'flag\{[0-9a-fA-F]+\}' "$log_file" | sort -u || true)

  if [ -n "$matches" ]; then
    printf "%s\n" "$matches" | while IFS= read -r f; do
      # For ONNX (multi-line clue), show the full output (already filtered by onnx_extract.sh)
      if [[ "$label" == *"ONNX"* ]]; then
        echo "Clue:"
        cat "$log_file" | tr -cd '[:print:]\t\n' | sed 's/^[[:space:]]*//'
      else
        # For others, show the line containing the flag
        clue_line=$(grep -a -m1 -F "$f" "$log_file" | tr -cd '[:print:]\t' | sed 's/^[[:space:]]*//' || true)
        if [ -n "$clue_line" ]; then
          echo "Clue: $clue_line"
        fi
      fi
      echo "Flag: $f"
      if ! grep -qF "$f" "$OUT"; then
        echo "$f" >> "$OUT"
      fi
    done
  else
    echo "Flag: (none found)"
  fi
  echo
}

run_and_extract "EXIF metadata" "bash exif.sh"
run_and_extract "Zero-width decoder" "$PYTHON decode_zero.py"
run_and_extract "ONNX strings search" "bash onnx_extract.sh"
run_and_extract "AES brute force" "$PYTHON brute_force.py"
run_and_extract "JSteg extractor" "$PYTHON last_flag.py"

echo "════════════════════════════════════════════════════════════════════"
echo "SUMMARY: All collected flags"
echo "════════════════════════════════════════════════════════════════════"
nl -ba "$OUT"
