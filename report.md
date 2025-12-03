# How I Solved the Comma.ai CTF

So comma.ai put out this CTF thing for their NeurIPS event. I got nerd-sniped hard. Here's how it went down.

## The Setup

Started at https://comma.ai/neurips and found an image called `comma_four.jpg`. When someone gives you a random JPEG in a CTF, you check the metadata first. Always.

## Flag 1: The Easy One

```bash
exiftool comma_four.jpg
```

Boom. Right there in the UserComment field:

> congratulations for finding the first flag{429e680b}

Classic EXIF hiding. The comment also told me to check out `https://commaai.github.io/model_reports/` for the next flag.

**Flag:** `429e680b`

## Flag 2: Invisible Characters

So I went to the model_reports site. Big directory listing with a bunch of UUID-looking folders. Poked around and eventually found a README.txt that looked normal... but wasn't.

Opened it in a hex editor and saw a bunch of zero-width Unicode characters sprinkled in. These are invisible characters that don't render but ARE there:

- `U+200B` - zero width space
- `U+200C` - zero width non-joiner  
- `U+200D` - zero width joiner
- etc.

Classic stego trick. Each invisible char maps to a bit. String them together, group into bytes, decode as ASCII.

Wrote a quick decoder:

```python
ZW = {
    "\u200b": "0",
    "\u200c": "1",
    "\u200d": "0",
    "\u200e": "1",
    "\u200f": "0",
}

def decode_zero_width(text):
    bits = "".join(ZW.get(c, "") for c in text)
    return "".join(
        chr(int(bits[i:i+8], 2))
        for i in range(0, len(bits), 8)
        if len(bits[i:i+8]) == 8
    )
```

The URL was `https://commaai.github.io/model_reports/429e680b-077d-461f-9df9-dd28aa0b6b26/400/README.txt` - notice the first flag's hash is part of the path. Cute.

**Flag:** `909636e2`

## Flag 3: Digging Through ONNX

Next clue pointed to the openpilot repo. There's a branch called `neurips-driving` that had something special.

```bash
git clone --depth=1 --no-single-branch https://github.com/commaai/openpilot.git
cd openpilot
git fetch --depth=1 origin neurips-driving
git checkout -f FETCH_HEAD
```

Then just ran strings on the model file:

```bash
strings -a selfdrive/modeld/models/driving_policy.onnx | grep -ni "flag{"
```

Found the third flag embedded as plain text in the ONNX model along with some context about a "European Central Bank code" and some hex blob. That was the hint for the next stage.

**Flag:** `b3a39a41`

## Flag 4: AES Brute Force

The ONNX file had this clue about "European Central Bank code" - which is a cheeky way of saying ECB mode (AES-ECB). Also mentioned CAN bus speed.

So the setup was:
- There's a hex blob (ciphertext) in the ONNX file
- Key is derived from a speed value: `md5(f"{speed:.1f}").digest()`
- The speed is somewhere in the range a car would go (0-60 m/s)

That's only 601 possible keys. Easy brute force.

```python
from hashlib import md5
from Crypto.Cipher import AES

for i in range(0, 600+1):
    x = i/10.0
    key = md5(f"{x:.1f}".encode()).digest()
    cipher = AES.new(key, AES.MODE_ECB)
    plaintext = cipher.decrypt(data)
    if b"flag{" in plaintext:
        print(f"Speed: {x:.1f} m/s")
        print(plaintext)
        break
```

The winning speed was somewhere in the 30s m/s range. Decrypted blob had the next flag.

**Flag:** `1205a94e` (from AES decryption)

## Flag 5: JSteg - The Hard One

Remember that `comma_four.jpg` from the beginning? Turns out it had ANOTHER flag hidden in it. Not in metadata this time - in the actual image data.

JSteg is a classic JPEG steganography technique. It hides data in the LSBs of the quantized DCT coefficients. Sounds fancy, but here's the deal:

1. JPEG compresses images by converting 8x8 pixel blocks into frequency coefficients (DCT)
2. These coefficients get quantized (rounded) to compress better
3. JSteg hides one bit per coefficient by tweaking the LSB
4. You skip DC coefficients and anything with absolute value ≤ 1

The tricky part is getting the order right. You have to:
- Go through blocks in row-major order (left to right, top to bottom)
- Within each block, follow zigzag order (standard JPEG thing)
- Skip index 0 (DC) and coefficients where |v| ≤ 1
- First 32 bits tell you how many bytes to read
- Then grab that many bytes worth of bits

```python
from jpegio import read

zigzag = [0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,
          12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,
          35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,
          58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63]

img = read("comma_four.jpg")
coefs = img.coef_arrays[0]
h, w = coefs.shape

bits = []
for by in range(0, h, 8):
    for bx in range(0, w, 8):
        blk = coefs[by:by+8, bx:bx+8]
        for idx in zigzag[1:]:  # skip DC
            r, c = divmod(idx, 8)
            v = int(blk[r, c])
            if abs(v) <= 1:
                continue
            bits.append(abs(v) & 1)

length = int(''.join(str(b) for b in bits[:32]), 2)
payload_bits = bits[32:32 + length*8]
# convert to bytes and decode
```

This one took a while to get right. Lots of subtle ways to mess it up - wrong zigzag order, including DC, wrong coefficient filtering, etc.

**Flag:** `36d0c194`

## Final Tally

| # | Flag | Method |
|---|------|--------|
| 1 | `429e680b` | EXIF metadata |
| 2 | `909636e2` | Zero-width Unicode stego |
| 3 | `b3a39a41` | Strings in ONNX model |
| 4 | `1205a94e` | AES-ECB brute force |
| 5 | `36d0c194` | JSteg DCT stego |

## What I Used

- `exiftool` - metadata extraction
- `jpegio` - reading JPEG DCT coefficients directly
- `pycryptodome` - AES decryption
- Python for scripting everything
- A lot of coffee

## Files in This Repo

- `exif.sh` - extracts EXIF metadata from the JPEG
- `decode_zero.py` - zero-width Unicode decoder
- `onnx_extract.sh` - clones repo and greps the ONNX file
- `brute_force.py` - AES key brute force
- `last_flag.py` - JSteg extraction
- `run.sh` - runs everything in order
- `comma_four.jpg` - the original image with flags 1 and 5

## Thoughts

The CTF had a nice difficulty curve. Flag 1 was trivial (check metadata, always), and they ramped up from there. The JSteg one was the real challenge - I went down several wrong paths before getting the coefficient selection rules exactly right.

The "European Central Bank code" hint for ECB was clever. And hiding two flags in the same image (metadata + DCT) was a nice twist.

Good CTF. Would solve again.
