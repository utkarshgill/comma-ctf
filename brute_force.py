#!/usr/bin/env python3
# step4_extract_and_bruteforce.py
# - reads ONNX at selfdrive/modeld/models/driving_policy.onnx
# - extracts long hex near "European Central Bank" or "European"
# - fixes odd-length hex if necessary
# - brute-forces speed x in 0.0..60.0 step 0.1 using key = md5(f"{x:.1f}").digest()
# - tries AES-CBC (iv=first16) and AES-ECB, prints plaintext when it finds flag{...}
#
# Requirements: pip install pycryptodome

import re, binascii, sys, os
from hashlib import md5
from Crypto.Cipher import AES

ONNX_PATH = "openpilot/selfdrive/modeld/models/driving_policy.onnx"

if not os.path.isfile(ONNX_PATH):
    print("ONNX not found at", ONNX_PATH); sys.exit(1)

b = open(ONNX_PATH, "rb").read()
txt = b.decode("utf-8", errors="ignore")

# 1) Find a marker near the clue
anchor = None
for marker in ("European Central Bank", "European Central Bank code", "European Central Bank code:"):
    idx = txt.find(marker)
    if idx != -1:
        anchor = idx
        break
# fallback: search for 'European' or 'Central Bank'
if anchor is None:
    anchor = txt.find("European")
if anchor == -1:
    anchor = 0

# 2) take a generous window after anchor and collect hex chars
start = max(0, anchor - 200)
end   = min(len(txt), anchor + 5000)   # expand if needed
window = txt[start:end]

# Extract candidates: contiguous hex groups (allow whitespace/newline between groups)
# Strategy: find groups of hex and also a long run of hex-like chars+whitespace then strip whitespace
cands_raw = re.findall(r'(?:[0-9a-fA-F]{20,}(?:\s+[0-9a-fA-F]{2,})*)', window, flags=re.S)
cands = []
for cr in cands_raw:
    cleaned = re.sub(r'\s+','', cr)
    if len(cleaned) >= 120:
        cands.append(cleaned)

# fallback: any long contiguous hex anywhere
if not cands:
    alt = re.findall(r'[0-9a-fA-F]{120,}', txt, flags=re.S)
    cands = alt

if not cands:
    print("No long hex found in ONNX window. Increase window or inspect file manually."); sys.exit(1)

hex_blob = max(cands, key=len).lower()

# Trim trailing odd nibble if present
if len(hex_blob) % 2 == 1:
    hex_blob = hex_blob[:-1]

data = binascii.unhexlify(hex_blob)
print("Found hex bytes:", len(data), "hex chars:", len(hex_blob))
print("prefix:", hex_blob[:64] + ("..." if len(hex_blob)>64 else ""))

def try_decrypt(key):
    iv, ct = data[:16], data[16:]
    # CBC
    try:
        p = AES.new(key, AES.MODE_CBC, iv).decrypt(ct)
        s = p.rstrip(b"\x00").decode("utf-8","ignore")
        if "flag{" in s:
            return ("CBC", s)
    except Exception:
        pass
    # ECB
    try:
        p = AES.new(key, AES.MODE_ECB).decrypt(data)
        s = p.rstrip(b"\x00").decode("utf-8","ignore")
        if "flag{" in s:
            return ("ECB", s)
    except Exception:
        pass
    return None

# brute force 0.0..60.0 by 0.1 (adjust if needed)
for i in range(0, 600+1):
    x = i/10.0
    key = md5(f"{x:.1f}".encode()).digest()
    res = try_decrypt(key)
    if res:
        mode, plaintext = res
        print("\nFOUND")
        print("speed (m/s):", f"{x:.1f}")
        print("key(hex):", key.hex())
        print("mode:", mode)
        print("plaintext:\n", plaintext)
        break
else:
    print("No flag found in 0.0-60.0 m/s range. Try expanding range or precision.")

