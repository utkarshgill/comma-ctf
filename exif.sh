#!/usr/bin/env bash
# expects comma_four.jpg in CWD
file comma_four.jpg
exiftool -s -UserComment -Comment -ImageDescription comma_four.jpg

