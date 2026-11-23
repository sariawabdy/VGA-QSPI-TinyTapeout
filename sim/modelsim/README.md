# Simulating the chip in ModelSim

This folder is `sim/modelsim/` in the repo. It uses the design files straight from the repo's `src/` folder,
so copy (or `git clone`) the **whole repo** to the lab PC, not just this folder.

| File | What it is |
|---|---|
| `../../src/` | the 4 design files (the repo's `src/`, used directly) |
| `tb_vga_qspi.v` | the testbench: clock, reset, flash on the uio pins, checks every pixel, PASS/FAIL, saves `frame.bmp` |
| `flash_model.v` | Verilog model of the W25Q128JV flash (commands 03h and 6Bh), loaded with `image.hex` |
| `image.hex` | the 160×120 image (19,200 bytes, `00RRGGBB`) |
| `run.do` | compile + simulate + waves, normal case |
| `run_late.do` | same test with slow pins (50 ns) and `ui_in[0] = 1` |

## Steps

1. Get the repo onto the lab PC: **Code → Download ZIP** on GitHub (or `git clone`), and unzip it somewhere simple,
   e.g. `C:\tt\VGA-QSPI-TinyTapeout` (no spaces or Hebrew in the path).
2. Open **ModelSim** (or Questa).
3. **File → Change Directory…** → choose the repo's `sim\modelsim` folder.
4. In the **Transcript** window at the bottom, type:
   ```
   do run.do
   ```
5. Wait. It simulates about 34 ms of chip time (one full frame and a bit), which takes from under a minute to a few minutes.
6. At the end the Transcript shows:
   ```
   pixels checked: 154240   pixel/sync errors: 0   bus fights: 0
   PASS  (picture saved as frame.bmp and frame.ppm)
   ```
   ModelSim then pauses at `$stop`; that's normal.
7. Double-click **`frame.bmp`** (in the same folder): it's the screen your chip drew in simulation.
   (`frame.ppm` is the same picture, for macOS Preview or GIMP.)
8. Optional: `do run_late.do` should also PASS.

## What it checks

- every pixel of a whole frame against `image.hex` (through flash → QSPI reader → VGA → pins)
- HSYNC / VSYNC in the right places
- the chip and the flash never drive the same IO pin at the same time
- the first line of the *next* frame (the read that starts during the last blank line)

## The Wave window

`run.do` adds the useful signals: the chip pins, the flash bus (CS_n, SCK, IO0–IO3) and the
QSPI reader's `state`, `row_start`, `row_base`, `pixel_valid`, `pixel_take`, `pixel_data`.
It zooms to 3400–3420 µs, inside a visible line. Use **zoom in / zoom out** to look around:
you'll see SCK pausing when the VGA hasn't taken a byte yet.

## If something goes wrong

| What you see | Fix |
|---|---|
| `** Error: (vsim-…) Can't open file image.hex` | ModelSim's directory isn't this folder: redo step 3 |
| `-voptargs` not recognized (very old ModelSim) | in `run.do`, change `vsim -voptargs=+acc` to `vsim -novopt` |
| "No license" when starting Questa | the Intel Questa Starter edition needs a free license file from Intel's Self-Service Licensing Center |
| FAIL with pixel errors | send the first ERROR lines from the Transcript |
