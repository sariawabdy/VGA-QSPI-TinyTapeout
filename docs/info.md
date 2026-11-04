<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The chip shows an image stored in an external QSPI flash on a VGA monitor. The image itself is not stored on the chip, which keeps the design small: it reads the bytes from the flash while the screen is being drawn.

**VGA side.** A standard 640×480 @ 60 Hz timing generator (25 MHz pixel clock, 800×525 total) drives HSYNC, VSYNC and 2 bits each of red, green and blue on the Tiny VGA pins. The image is up to 160×120 pixels, one byte per pixel in `00RRGGBB` (RGB222) format, stored row by row. Every image pixel is shown as a 4×4 block, so a 160×120 image fills the screen; it is centered.

**Flash side.** The flash is a Winbond W25Q128JV on the Tiny Tapeout QSPI Pmod. During the horizontal blanking of each line, the VGA side sends the start address of the next line's image row, and the QSPI reader starts a *Fast Read Quad Output* (6Bh) command: 8 command + 24 address clocks on IO0, 8 dummy clocks, then data on IO0–IO3, 4 bits per SCK. SCK is the 25 MHz clock divided by 2, which delivers exactly one byte every 4 clocks: one image pixel's worth. The reader keeps a byte ready ahead of time and pauses SCK whenever the VGA side hasn't taken it yet. Each image row is read again for each of its 4 screen lines, so no line buffer is needed.

**Read timing (`ui[0]`).** Data from the flash has to travel out through the chip's pins and back. `ui[0]` selects when the reader samples it: `0` = one clock (40 ns) after the flash changes its data, `1` = two clocks (80 ns) after. Use `1` if the pins turn out to be slow.

## How to test

1. **Put the image in the flash** at address `0x000000`: 19,200 bytes (160×120), row by row from the top-left pixel, one byte per pixel in `00RRGGBB` format. The flash's **Quad Enable (QE)** bit must be 1 (first-party Tiny Tapeout QSPI Pmods ship with it set; otherwise set it once, for example with the QSPI Pmod activation script).
2. Plug the **QSPI Pmod** into the bidirectional (uio) Pmod header and the **Tiny VGA Pmod** into the output (uo) header, and connect a VGA monitor.
3. Set the clock to **25 MHz** (25.175 MHz is the exact VGA value; 25 MHz works on most monitors).
4. Set **`ui[0]` = 0**, then reset the design. The image should appear.
5. If the picture is garbled or the colors are wrong, set **`ui[0]` = 1** (late sampling) and reset again.

Note: the very first screen line after reset is black (its data was not prefetched yet); from the second line on, and on every following frame, the image is complete.

## External hardware

- [Tiny Tapeout QSPI Pmod](https://store.tinytapeout.com/), with the W25Q128JV flash (the two RAM chips on it are not used and are kept deselected)
- Tiny VGA Pmod and a VGA monitor
