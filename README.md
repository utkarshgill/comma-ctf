# solving the comma.ai ctf

**spoiler warning**: this contains complete [solutions](https://github.com/utkarshgill/comma-ctf) to all five flags from the comma.ai neurips ctf. if you want to solve it yourself first, stop reading.

---

comma.ai released a ctf for their neurips event. this was my first ctf. it took two days.

## starting point

the challenge was at https://comma.ai/neurips. there was an image file called `comma_four.jpg`.

![comma_four](https://github.com/user-attachments/assets/1e2d0e3a-2a5b-46e4-9c66-6349f25ee745)

## flag 1 - exif metadata

ran exiftool on the image.

```bash
exiftool comma_four.jpg
```

the usercomment field contained the first flag.

```
congratulations for finding the first flag{429e680b} flags have this format flag{x} 
please submit x (429e680b in this case) to the following link: 
https://forms.gle/LeytrGCMoicWiyvb8 then go to https://commaai.github.io/model_reports 
for the next flag. Remember this flag, and the next ones you find, they might be useful! 
If the flag requires going to other territories, it will be very explicit, with a clear 
instruction saying to go somewhere 'for the next flag'. Good luck!
```

**flag 1:** `429e680b`

## flag 2 - zero-width unicode stego

the model_reports directory had many subdirectories. what what what... a uuid starting with the flag we just found... well WHAT ARE THE ODDS?!

there was a readme file that looked normal but had invisible unicode characters embedded in it.

![model reports](https://github.com/user-attachments/assets/b2611b13-e95c-45c5-aea6-11bb004b3f77)

these characters were:
- U+200B (zero width space)
- U+200C (zero width non-joiner)
- U+200D (zero width joiner)
- U+200E (left-to-right mark)
- U+200F (right-to-left mark)

each character type maps to a bit. figuring out which character maps to 0 or 1 was trial and error:

1. extract all zero-width characters from the file
2. try a mapping (e.g., U+200B=0, U+200C=1, ...)
3. group resulting bits into 8-bit chunks
4. decode as ascii
5. if output is readable text, the mapping is correct. if garbage, try another mapping.

the mapping that worked: **U+200C and U+200E = 1, everything else = 0**. i wrote a decoder:

```python
import sys

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

this decoded to the second flag and a message about checking the openpilot repository.

```
congratulations for finding the second flag{909636e2}. find the next flag in the 
openpilot repository, don't forget the branches!
```

**flag 2:** `909636e2`

## flag 3 - text in onnx model

cloned the openpilot repo and checked out the `neurips-driving` branch.

```bash
git clone --depth=1 --no-single-branch https://github.com/commaai/openpilot.git
cd openpilot
git fetch --depth=1 origin neurips-driving
git checkout -f FETCH_HEAD
```

ran strings on the model file:

```bash
strings -a selfdrive/modeld/models/driving_policy.onnx | grep -ni "flag{"
```

found the third flag as plain text in the onnx file.

```
congratulations for finding the third flag{b3a39a41}
for the next flag: go to hf/datasets/commaai/comma2k19
the names are Vincent Rijmen and Joan Daemen
the dongle_id is b0c9d2329ad1606b
the date is 2018-08-16
the time is 21-52-30
the CAN boot time is around 17602.32
the CAN speed is x m/s
the key is md5(x:.1f).digest() # 128 bits
European Central Bank code:
55c2ffe03e69a22836834f26e4deb10d71b6b704c99faf39357587516a58b096c8ea3ecc0800fec4ac501b52cca00903011e34d604ed6b9b99e88b5571f3876bb0370
```

this contained references to vincent rijmen and joan daemen (creators of aes), a dongle_id, timestamp, and the encryption key derivation and ciphertext.

**flag 3:** `b3a39a41`

## flag 4 - aes brute force

the "european central bank" hint pointed to ecb mode (aes-ecb). the hex string was ciphertext. the key derivation was md5 of a speed value formatted as a single-decimal float.

car speeds are bounded, so 0-60 m/s at 0.1 increments gives 601 possibilities. brute force was feasible.

i wrote a script that extracted the hex ciphertext directly from the onnx file and tried each possible speed:

```python
from hashlib import md5
from Crypto.Cipher import AES
import binascii

# extract hex blob from onnx (see brute_force.py for full extraction logic)
hex_blob = "55c2ffe03e69a22836834f26e4deb10d71b6b704c99faf39357587516a58b096..."
data = binascii.unhexlify(hex_blob)

for i in range(0, 600+1):
    x = i/10.0
    key = md5(f"{x:.1f}".encode()).digest()
    
    try:
        p = AES.new(key, AES.MODE_ECB).decrypt(data)
        s = p.rstrip(b"\x00").decode("utf-8", "ignore")
        if "flag{" in s:
            print(f"speed: {x:.1f} m/s")
            print(s)
            break
    except:
        pass
```

the correct speed was 30.8 m/s.

```
congratulations on finding the fourth flag{1205a94e}. go to the comma_four.jpg image 
again for the last flag. Derek Upham. left to right, top to bottom, 8x8 zig-zag. 
[first 32 bits = payload length (in bytes)] [payload]
```

this told me to go back to the original image and mentioned derek upham (creator of jsteg) and specific extraction instructions.

**flag 4:** `1205a94e`

## flag 5 - jsteg

derek upham created jsteg, a jpeg steganography tool. it hides data in the lsb of jpeg's quantized dct coefficients.

jpeg compression:
- splits image into 8x8 blocks
- applies dct (converts to frequency domain)
- quantizes the coefficients (rounds them for compression)

jsteg embeds bits in these quantized coefficients. extraction rules:
- skip dc coefficient (index 0)
- skip coefficients where `|value| ≤ 1`
- traverse blocks row-major (left to right, top to bottom)
- within each block use zigzag scan order
- extract lsb of each remaining coefficient
- first 32 bits encode payload length (bytes)
- next (length × 8) bits are the payload

getting this right required precision. wrong coefficient selection, wrong traversal order, or wrong byte assembly all produce garbage because the length field becomes invalid.

```python
from jpegio import read

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
        for idx in zz[1:]:
            r, c = divmod(idx, 8)
            v = int(blk[r, c])
            if abs(v) <= 1:
                continue
            bits.append(abs(v) & 1)

length = bits_to_int(bits[:32])
payload_bits = bits[32:32 + length*8]
payload = bits_to_bytes(payload_bits)

print(payload.decode('utf-8'))
```

```
congratulations for finding the last flag{36d0c194}
```

**flag 5:** `36d0c194`

## summary

| # | flag | method |
|---|------|--------|
| 1 | `429e680b` | exif metadata |
| 2 | `909636e2` | zero-width unicode stego |
| 3 | `b3a39a41` | strings in onnx model |
| 4 | `1205a94e` | aes-ecb brute force |
| 5 | `36d0c194` | jsteg dct stego |

## files in this repo

- `exif.sh` - extracts exif metadata
- `decode_zero.py` - decodes zero-width unicode
- `onnx_extract.sh` - clones openpilot and extracts from onnx
- `brute_force.py` - brute forces aes key
- `last_flag.py` - extracts jsteg payload
- `run.sh` - orchestrator that runs all steps
- `comma_four.jpg` - original challenge image

## tools

- exiftool - metadata extraction
- jpegio - reading jpeg dct coefficients
- pycryptodome - aes decryption
- strings, grep, git - basic unix tools
- python - scripting

## what worked

- start with cheap tests (metadata, strings)
- follow the clues in order
- validate each step before moving on
- when extraction fails, it's usually a tiny detail (endianness, coefficient filter, byte order)
- simple and reproducible scripts, parameter sweeps when stuck

## what made this hard

flag 5 was the main difficulty. jsteg extraction fails catastrophically with small mistakes:
- including zeros when you should skip them
- including `±1` coefficients when you should skip them  
- wrong zigzag order
- wrong byte bit order
- wrong endianness for length field
- including dc coefficient

each wrong choice makes the length field decode to garbage (e.g., 2 million bytes instead of 51), and the entire extraction fails.

the solution required understanding the exact jsteg convention and implementing it precisely.

## what i learned

this was my first ctf and i learned a lot:

**metadata hiding**: always check metadata first. it's the easiest place to hide information and costs almost nothing to check.

**zero-width unicode stego**: invisible characters encode bits. mapping: each character type → 0 or 1. bits → bytes → ascii.

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

## notes

the difficulty curve was good. flag 1 was easy enough that i could get started. flags 2 and 3 introduced new concepts but were still approachable. flag 4 required understanding crypto basics. flag 5 was genuinely hard - i tried many wrong approaches before getting the coefficient selection rules exactly right.

the hints were clever. "european central bank code" for ecb mode was a cute touch. "derek upham" pointing to jsteg was a nice history lesson.

hiding two separate flags in the same image (exif + dct) was cool. made me come back full circle to the image i started with.

overall, this was a great learning experience. i now understand steganography, basic cryptanalysis, and jpeg internals much better than before. would recommend to anyone wanting to learn these topics.


