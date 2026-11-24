# Testing on the DE10-Lite with Quartus

Two ready-made Quartus projects in `fpga/de10lite/`. Pins, clock and settings are already filled in.
The main project uses the design files straight from the repo's `src/` folder, so get the **whole repo**
onto the lab PC (GitHub **Code → Download ZIP**, or `git clone`), into a simple path without spaces or Hebrew.

| Folder | Project file | What it does | When |
|---|---|---|---|
| `writer/` | `flash_writer_de10.qpf` | writes the image into the QSPI Pmod's flash, turns on Quad Enable, checks it | **once** (or when the image changes) |
| `main/` | `vga_qspi_de10.qpf` | your real Tiny Tapeout design, drawing the image on VGA | every test |

You need: a lab PC with **Quartus Prime Lite** (with **MAX 10** device support), the DE10-Lite + USB cable,
the QSPI Pmod, jumper wires, a VGA monitor.

## 0. Wire the QSPI Pmod to the GPIO header (JP1), power OFF

| Pmod pin | Signal | DE10-Lite JP1 pin |
|---|---|---|
| 1 | flash /CS | 1 |
| 2 | IO0 | 2 |
| 3 | IO1 | 3 |
| 4 | SCK | 4 |
| 7 | IO2 | 5 |
| 8 | IO3 | 6 |
| 9 | RAM A /CS | 7 |
| 10 | RAM B /CS | 8 |
| 5 or 11 | GND | **12** or **30** |
| 6 or 12 | 3.3 V | **29** |

⚠️ **JP1 pin 11 is 5 V. Never connect it to the Pmod.** Check the Pmod's pin 1 on its silkscreen. Short wires.

## 1. Write the image into the flash

1. Quartus: **File → Open Project** → `fpga/de10lite/writer/flash_writer_de10.qpf`.
2. **Processing → Start Compilation** (Ctrl+L). Wait for "Full Compilation was successful".
3. **Tools → Programmer**:
   - **Hardware Setup…** → choose **USB-Blaster** → Close
   - Mode **JTAG**; the file `output_files/flash_writer_de10.sof` should be listed (if not: **Add File…**)
   - tick **Program/Configure** → **Start**
4. Look at the board (takes well under a second):
   - **HEX displays: `EF7018`** → flash found, wiring OK
   - **LEDR[1] on** → image written **and verified** ✅
   - **LEDR[2] on** → error, code on **LEDR[5:4]**:
     `01` no/wrong ID → wiring or 3.3 V · `10` Quad Enable won't set · `11` read-back mismatch
   - **LEDR[9]** blinks = design running
5. **KEY[0]** runs it again.

## 2. Run the real design

1. **File → Open Project** → `fpga/de10lite/main/vga_qspi_de10.qpf`.
2. **Processing → Start Compilation**.
3. **Tools → Timing Analyzer** (or the compilation report → **Timing Analyzer → Summary**):
   the 25 MHz clock must show **no negative slack** (no red).
4. **Tools → Programmer** → `output_files/vga_qspi_de10.sof` → **Start**.
5. Connect the VGA monitor. **SW[0] = down (0)**. Press **KEY[0]**. The image appears.
   LEDs: `LEDR[0]` PLL locked · `LEDR[1]` running · `LEDR[2]` = SW[0] · `LEDR[3]` flash being read.

Programming with a `.sof` is temporary: it's gone after power-off. Just program it again.

## If something goes wrong

| What you see | Likely cause |
|---|---|
| Compile error about `altpll` / `pll_25` | Make the PLL with the wizard instead: remove `pll_25.v` from the project (Project → Add/Remove Files), then **IP Catalog → ALTPLL**, name `pll_25`, Verilog, input **50 MHz**, output **c0 = 25 MHz**, keep **locked**, untick **areset**. Add the generated `pll_25.qip`. |
| Error about memory initialization / ERAM (writer) | **Assignments → Device → Device and Pin Options → Configuration**: Configuration mode = **Single Uncompressed Image with Memory Initialization**. |
| Programmer shows "No Hardware" | USB-Blaster driver not installed: it's in the Quartus install folder `drivers/usb-blaster`. |
| HEX shows `000000` or `FFFFFF` | wiring, 3.3 V/GND, or Pmod pin order |
| Monitor says "no signal" | `LEDR[0]` off → PLL problem; `LEDR[1]` off → press KEY[0] |
| Picture but wrong/garbled colors | flash not written (run step 1), or try `SW[0]` = up |
| Black screen with sync | flash empty or Quad Enable off → run step 1 again |

## What's inside

- `../../src/` (the repo's `src/`): the four design files, used directly
- `main/de10lite_top.v`: board wrapper (PLL, reset, VGA DAC, tri-state GPIO for the Pmod)
- `main/pll_25.v`: 50 → 25 MHz PLL (Intel `altpll` block)
- `writer/flash_writer.v`, `writer/de10lite_flash_writer_top.v`, `writer/image.hex` (19,200 bytes)
- `*.qsf`: device + all pin locations (from the DE10-Lite manual), `*.sdc`: clock constraints
- `tools/make_projects.py`: regenerates the `.qpf/.qsf/.sdc` files (`python3 tools/make_projects.py .` from `fpga/de10lite`)
- `tools/bin_to_hex.py`: makes `writer/image.hex` from a new image `.bin` (19,200 bytes for 160×120)
