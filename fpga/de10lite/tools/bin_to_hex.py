"""
bin_to_hex.py - turn the image .bin (from image_tools.py) into image.hex,
the file flash_writer.v loads into the FPGA's memory with $readmemh.

Usage:
    python3 bin_to_hex.py image_rgb222_160x120.bin image.hex

Prints the byte count: it must match IMG_SIZE in flash_writer (19200 for 160x120).
"""

import sys
from pathlib import Path


def bin_to_hex(bin_path, hex_path):
    data = Path(bin_path).read_bytes()
    Path(hex_path).write_text("".join(f"{b:02x}\n" for b in data))
    return len(data)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    n = bin_to_hex(sys.argv[1], sys.argv[2])
    print(f"wrote {n} bytes to {sys.argv[2]} (set IMG_SIZE = {n})")
