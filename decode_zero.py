#!/usr/bin/env python3
import sys
from urllib.request import urlopen

URL = "https://commaai.github.io/model_reports/429e680b-077d-461f-9df9-dd28aa0b6b26/400/README.txt"

def fetch():
    with urlopen(URL) as r:
        return r.read().decode(errors="ignore")

def decode_zero_width(text):
    # only U+200B and U+200C appear in the file: U+200B=0, U+200C=1
    bits = "".join("0" if c == "\u200b" else "1" if c == "\u200c" else "" for c in text)
    return "".join(
        chr(int(bits[i:i+8], 2))
        for i in range(0, len(bits), 8)
        if len(bits[i:i+8]) == 8
    )

if __name__ == "__main__":
    txt = fetch()
    sys.stdout.write(decode_zero_width(txt))

