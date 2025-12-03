from jpegio import read

# Standard JPEG zigzag order
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

# --- Load JPEG coefficients ---
img = read("comma_four.jpg")
coefs = img.coef_arrays[0]
h, w = coefs.shape

# --- Extract bits using strict JSteg rules ---
bits = []
for by in range(0, h, 8):
    for bx in range(0, w, 8):
        blk = coefs[by:by+8, bx:bx+8]
        for idx in zz[1:]:      # skip DC (index 0)
            r, c = divmod(idx, 8)
            v = int(blk[r, c])
            if abs(v) <= 1:     # skip unusable coefficients
                continue
            bits.append(abs(v) & 1)

# --- Decode ---
length_bits = bits[:32]
length = bits_to_int(length_bits)
payload_bits = bits[32:32 + length*8]
payload = bits_to_bytes(payload_bits)

print(payload.decode('utf-8'))
