"""Convert PNG images to and from the RGB222 format used by this VGA/QSPI project.

The external flash stores *one byte per pixel* with the bit layout 00RRGGBB.
Each color channel is two bits wide (0..3), for 64 possible colors.
The default 160x120 source image is displayed at 640x480 with 4x scaling.

Examples:
    python image_tools.py encode photo.png
    # Writes photo_rgb222.bin and photo_rgb222.mem

    python image_tools.py encode photo.png --preview photo_preview.png
    python image_tools.py decode photo_rgb222.bin --output reconstructed.png --scale 4

The .bin file is suitable for loading into flash_sim.W25Q128JV(init_data=...).
The .mem file contains one hexadecimal byte per line for Verilog $readmemh.
"""

import argparse
from pathlib import Path
from PIL import Image

DEFAULT_WIDTH = 160
DEFAULT_HEIGHT = 120


def pack_rgb222(red: int, green: int, blue: int) -> int:
    """Pack 8-bit RGB values into 00RRGGBB (top two bits of each channel)."""
    return ((red >> 6) << 4) | ((green >> 6) << 2) | (blue >> 6)


def unpack_rgb222(pixel: int) -> tuple[int, int, int]:
    """Expand one RGB222 pixel to 8-bit RGB for image reconstruction."""
    red = (pixel >> 4) & 0x03
    green = (pixel >> 2) & 0x03
    blue = pixel & 0x03
    return red * 85, green * 85, blue * 85


def image_to_rgb222_bytes(image: Image.Image, width: int = DEFAULT_WIDTH,
                          height: int = DEFAULT_HEIGHT) -> bytes:
    """Resize an image and return one RGB222 byte per source pixel, row-major."""
    if width <= 0 or height <= 0:
        raise ValueError("Image width and height must be positive")
    rgb = image.convert("RGB")
    if rgb.size != (width, height):
        rgb = rgb.resize((width, height), Image.Resampling.LANCZOS)
    return bytes(pack_rgb222(r, g, b) for r, g, b in rgb.getdata())


def rgb222_bytes_to_image(pixel_bytes: bytes, width: int = DEFAULT_WIDTH,
                          height: int = DEFAULT_HEIGHT, scale: int = 1) -> Image.Image:
    """Reconstruct RGB222 bytes as an RGB PNG-compatible PIL Image."""
    if width <= 0 or height <= 0 or scale <= 0:
        raise ValueError("Width, height and scale must be positive")
    expected_bytes = width * height
    if len(pixel_bytes) != expected_bytes:
        raise ValueError(
            f"Expected {expected_bytes} bytes ({width}x{height}), "
            f"received {len(pixel_bytes)}"
        )
    rgb_pixels = [unpack_rgb222(pixel) for pixel in pixel_bytes]
    image = Image.new("RGB", (width, height))
    image.putdata(rgb_pixels)
    if scale != 1:
        image = image.resize((width * scale, height * scale), Image.Resampling.NEAREST)
    return image


def write_rgb222_mem(pixel_bytes: bytes, path: Path) -> None:
    """Write $readmemh-compatible data: one uppercase hexadecimal byte per line."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{pixel:02X}\n" for pixel in pixel_bytes), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description="PNG <-> RGB222 flash image converter (00RRGGBB)")
    commands = parser.add_subparsers(dest="command", required=True)

    enc = commands.add_parser("encode", help="PNG -> RGB222 .bin and .mem")
    enc.add_argument("image", type=Path, help="Input PNG/JPEG/etc.")
    enc.add_argument("--width", type=int, default=DEFAULT_WIDTH)
    enc.add_argument("--height", type=int, default=DEFAULT_HEIGHT)
    enc.add_argument("--bin", type=Path, default=None, help="Output raw bytes (.bin)")
    enc.add_argument("--mem", type=Path, default=None, help="Output $readmemh data (.mem)")
    enc.add_argument("--preview", type=Path, default=None,
                     help="Optional 4x preview of quantized image (.png)")

    dec = commands.add_parser("decode", help="RGB222 .bin -> reconstructed PNG")
    dec.add_argument("image", type=Path, help="Input raw pixel bytes (.bin)")
    dec.add_argument("--width", type=int, default=DEFAULT_WIDTH)
    dec.add_argument("--height", type=int, default=DEFAULT_HEIGHT)
    dec.add_argument("--scale", type=int, default=1, help="Nearest-neighbor scale (4 => VGA size)")
    dec.add_argument("--output", type=Path, default=None, help="Output reconstructed PNG")

    args = parser.parse_args()
    if args.command == "encode":
        with Image.open(args.image) as image:
            pixels = image_to_rgb222_bytes(image, args.width, args.height)
        bin_path = args.bin or args.image.with_name(f"{args.image.stem}_rgb222.bin")
        mem_path = args.mem or args.image.with_name(f"{args.image.stem}_rgb222.mem")
        bin_path.parent.mkdir(parents=True, exist_ok=True)
        bin_path.write_bytes(pixels)
        write_rgb222_mem(pixels, mem_path)
        print(f"Saved {len(pixels):,} RGB222 bytes to {bin_path}")
        print(f"Saved Verilog memory initialization data to {mem_path}")
        if args.preview:
            args.preview.parent.mkdir(parents=True, exist_ok=True)
            rgb222_bytes_to_image(pixels, args.width, args.height, scale=4).save(args.preview)
            print(f"Saved quantized preview to {args.preview}")
    else:
        pixels = args.image.read_bytes()
        image = rgb222_bytes_to_image(pixels, args.width, args.height, args.scale)
        out_path = args.output or args.image.with_name(f"{args.image.stem}_reconstructed.png")
        out_path.parent.mkdir(parents=True, exist_ok=True)
        image.save(out_path)
        print(f"Reconstructed {len(pixels):,} bytes to {out_path}")


if __name__ == "__main__":
    main()
