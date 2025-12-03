# solving the comma.ai ctf - my first ctf experience

this was my first real ctf. comma.ai put out this challenge as part of their neurips event, and i decided to give it a shot. it took me about two days of work, and i learned a lot along the way.

## starting point

the challenge started at https://comma.ai/neurips with an image file called `comma_four.jpg`. i didn't really know where to begin, so i started with what seemed like the simplest thing - checking if there was anything hidden in the image metadata.

## flag 1 - exif metadata

i ran exiftool on the image:

```bash
exiftool comma_four.jpg
```

found the first flag right there in the UserComment field:

```
congratulations for finding the first flag{429e680b}
```

the comment also told me to go to https://commaai.github.io/model_reports/ for the next flag. this seemed straightforward enough.

**flag 1:** `429e680b`

## flag 2 - zero-width unicode steganography

i browsed the model_reports directory and eventually found a README.txt file. it looked like normal text, but when i examined it more carefully, i noticed there were invisible unicode characters embedded in it.

these were zero-width characters like:
- U+200B (zero width space)
- U+200C (zero width non-joiner)
- U+200D (zero width joiner)

each character could represent a bit (0 or 1). i wrote a small python decoder that:
1. extracted only the zero-width characters
2. mapped each character type to a bit
3. grouped the bits into bytes
4. decoded the bytes as ascii

the decoder was pretty simple:

```python
ZW_MAP = {
    "\u200b": "0",
    "\u200c": "1",
    "\u200d": "0",
    "\u200e": "1",
    "\u200f": "0",
}

data = sys.stdin.read()
bits = "".join(ZW_MAP.get(c, "") for c in data)
out = "".join(chr(int(bits[i:i+8], 2)) for i in range(0, len(bits), 8) if len(bits[i:i+8]) == 8)
print(out)
```

this gave me the second flag and told me to look in the openpilot repository.

**flag 2:** `909636e2`

## flag 3 - text hidden in onnx model

the clue said to check the openpilot repository and mentioned not to forget about branches. i cloned the repo and checked out the `neurips-driving` branch:

```bash
git clone --depth=1 --no-single-branch https://github.com/commaai/openpilot.git
cd openpilot
git fetch --depth=1 origin neurips-driving
git checkout -f FETCH_HEAD
```

then i ran strings on the onnx model file to find readable text:

```bash
strings -a selfdrive/modeld/models/driving_policy.onnx | grep -ni "flag{"
```

this found the third flag embedded as plain text. the same text also contained a clue about a "european central bank code" and a long hex string, plus information about:
- dongle_id: b0c9d2329ad1606b
- date: 2018-08-16
- time: 21-52-30
- can speed is x m/s
- key is md5(x:.1f).digest()

**flag 3:** `b3a39a41`

## flag 4 - aes brute force

this is where it got more interesting. the "european central bank code" hint was pointing to ecb mode (aes-ecb). the long hex string was the encrypted data.

the key was supposed to be derived from a can bus speed value formatted as a float with one decimal place, then hashed with md5. since car speeds are reasonable numbers (0-60 m/s seemed like a good range), the search space was only 601 possible values.

i wrote a brute force script:

```python
from hashlib import md5
from Crypto.Cipher import AES
import binascii

hex_blob = "55c2ffe03e69a22836834f26e4deb10d71b6b704c99faf39357587516a58b096..."
data = binascii.unhexlify(hex_blob)

for i in range(0, 600+1):
    x = i/10.0
    key = md5(f"{x:.1f}".encode()).digest()
    
    # try ecb
    try:
        p = AES.new(key, AES.MODE_ECB).decrypt(data)
        s = p.rstrip(b"\x00").decode("utf-8", "ignore")
        if "flag{" in s:
            print(f"found at speed: {x:.1f} m/s")
            print(s)
            break
    except:
        pass
```

the correct speed turned out to be 30.8 m/s. the decrypted message contained the fourth flag and told me to go back to the original image for the last flag, with a hint about "derek upham" and "8x8 zig-zag".

**flag 4:** `1205a94e`

## flag 5 - jsteg (jpeg dct steganography)

this was the hardest part for me. "derek upham" refers to the creator of jsteg, a classic jpeg steganography tool. it hides data in the least significant bits of jpeg's quantized dct coefficients.

here's what i learned about how jpeg compression works:
- images are divided into 8x8 pixel blocks
- each block is transformed into 64 frequency coefficients (dct)
- these coefficients are quantized (rounded) for compression
- jsteg hides bits in the lsb of these quantized values

the extraction rules for jsteg are very specific:
- skip the dc coefficient (index 0 in each block)
- skip coefficients where absolute value ≤ 1 (they're too small/unstable)
- traverse blocks in row-major order (left to right, top to bottom)
- within each block, follow zigzag scan order
- take the lsb of each usable coefficient
- first 32 bits = payload length in bytes
- next (length * 8) bits = the actual message

i spent a lot of time getting this wrong. if you include zeros when you shouldn't, or use the wrong byte order, or forget to skip the dc coefficient, the first 32 bits become garbage and the whole decode fails.

the final working extractor:

```python
from jpegio import read

# standard jpeg zigzag order
zz = [
 0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,
 12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,
 35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,
 58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63
]

def bits_to_int(b):
    return int(''.join(str(x) for x in b), 2)

def bits_to_bytes(bits):
    out = bytearray()
    for i in range(0, len(bits), 8):
        chunk = bits[i:i+8]
        if len(chunk) < 8:
            chunk += [0]*(8-len(chunk))
        out.append(int(''.join(str(x) for x in chunk), 2))
    return bytes(out)

img = read("comma_four.jpg")
coefs = img.coef_arrays[0]
h, w = coefs.shape

bits = []
for by in range(0, h, 8):
    for bx in range(0, w, 8):
        blk = coefs[by:by+8, bx:bx+8]
        for idx in zz[1:]:      # skip dc (index 0)
            r, c = divmod(idx, 8)
            v = int(blk[r, c])
            if abs(v) <= 1:     # skip unusable coefficients
                continue
            bits.append(abs(v) & 1)

length_bits = bits[:32]
length = bits_to_int(length_bits)
payload_bits = bits[32:32 + length*8]
payload = bits_to_bytes(payload_bits)

print(payload.decode('utf-8'))
```

**flag 5:** `36d0c194`

## all five flags

| # | flag | method |
|---|------|--------|
| 1 | `429e680b` | exif metadata |
| 2 | `909636e2` | zero-width unicode stego |
| 3 | `b3a39a41` | strings in onnx model |
| 4 | `1205a94e` | aes-ecb brute force |
| 5 | `36d0c194` | jsteg dct stego |

## tools i used

- exiftool - for extracting exif metadata
- jpegio - python library for reading jpeg dct coefficients
- pycryptodome - for aes decryption
- basic unix tools (strings, grep, git)
- python for all the extraction scripts

## what i learned

this was my first ctf and i learned a lot:

**metadata hiding**: always check metadata first. it's the easiest place to hide information and costs almost nothing to check.

**unicode steganography**: invisible unicode characters can encode binary data. they survive copy-paste and look normal in most editors.

**binary inspection**: large binary files like models often contain plaintext metadata. the `strings` command is your friend.

**cryptography basics**: 
- aes ecb vs cbc modes
- how initialization vectors work
- md5 as a key derivation (not secure, but works for ctf)
- why small search spaces enable brute force

**jpeg internals**:
- how jpeg compression works (dct → quantization → entropy coding)
- what dct coefficients represent (frequencies, not pixels)
- why jpeg uses 8x8 blocks
- zigzag scan order
- why steganography uses quantized coefficients (changing lsb barely affects image)

**jsteg specifically**:
- skip dc coefficient (too visible if modified)
- skip small coefficients (|v| ≤ 1 are unstable)
- use strict zigzag order
- extract bits in exact jpeg encoding order
- payload framing with length header

**debugging approach**:
- start with cheap tests (metadata, strings)
- follow the clues in order
- validate each step before moving on
- when extraction fails, it's usually a tiny detail (endianness, coefficient filter, byte order)
- keep scripts simple and reproducible

## files in this repo

- `exif.sh` - extracts exif metadata
- `decode_zero.py` - decodes zero-width unicode
- `onnx_extract.sh` - clones openpilot and extracts from onnx
- `brute_force.py` - brute forces aes key
- `last_flag.py` - extracts jsteg payload
- `run.sh` - orchestrator that runs all steps
- `comma_four.jpg` - original challenge image

## reflections

the difficulty curve was good. flag 1 was easy enough that i could get started. flags 2 and 3 introduced new concepts but were still approachable. flag 4 required understanding crypto basics. flag 5 was genuinely hard - i tried many wrong approaches before getting the coefficient selection rules exactly right.

the hints were clever. "european central bank code" for ecb mode made me smile. "derek upham" pointing to jsteg was a nice historical reference.

hiding two separate flags in the same image (exif + dct) was a good design choice. it made me come back to a file i thought i was done with.

overall, this was a great learning experience. i now understand steganography, basic cryptanalysis, and jpeg internals much better than before. would recommend to anyone wanting to learn these topics.

## acknowledgments

i used an ai assistant (chatgpt) as a thinking partner throughout this process. it helped me brainstorm approaches, understand concepts i was unfamiliar with (especially jpeg internals and jsteg), and debug when i got stuck. but i wrote and ran every script myself, and i can explain every step of the solution.

being honest about using help is important. in real work you use whatever resources are available - documentation, stack overflow, colleagues, ai tools. what matters is that you understand what you're doing and can reproduce and explain your work.
