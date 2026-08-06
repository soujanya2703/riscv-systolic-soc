# RISC-V SoC with Systolic Array ML Accelerator

A custom System-on-Chip (SoC) implemented in Verilog, integrating a **PicoRV32 RISC-V CPU** with a **weight-stationary systolic array** for hardware-accelerated matrix multiplication. The CPU communicates with the accelerator over a memory-mapped AXI4-Lite bus.

**Status:** Functionally verified end-to-end via RTL simulation (Icarus Verilog + Vivado XSim). Synthesis/implementation and physical hardware bring-up pending FPGA board access.

---

## Architecture Overview

**soc_top** wires together four blocks on a single shared memory bus, arbitrated by address:

- **PicoRV32 (RISC-V CPU, bus master)** — fetches instructions and issues reads/writes
- **Program/Data Memory (BRAM)** — `0x0000_0000`, holds firmware instructions + data
- **AXI4-Lite Interface → Systolic Array** — `0x8000_00xx`, CPU writes program the accelerator (control / weights / activations); the array computes weight-stationary MACs
- **LED/GPIO register** — `0x8000_0010`, write-only output for observability
- **Result readback** — `0x8000_00x0`, CPU reads back accumulated PE outputs

```
CPU ──┬──▶ Program/Data Memory   (0x0000_0000)
      ├──▶ AXI4-Lite ──▶ Systolic Array   (0x8000_0000–0008)
      ├──▶ LED / GPIO register            (0x8000_0010)
      └──◀ Result readback                (0x8000_0020–002C)
```


The CPU boots by fetching real instructions out of on-chip program memory, issues memory-mapped writes to program the accelerator, and reads back the computed result — closing the loop entirely in hardware/firmware, not just testbench stimulus.

---

## File Structure

| File | Description |
|---|---|
| `soc_top.v` | Top-level SoC module; memory, CPU, and accelerator address decode |
| `mem.v` | Synthesizable program/data memory (BRAM), loaded via `$readmemh` from `firmware.hex` |
| `picorv32.v` | PicoRV32 RISC-V CPU core (open-source, third-party) |
| `axi_interface.v` | AXI4-Lite slave interface with address-decode FSM |
| `systolic_array.v` | Parameterized NxN systolic array, generated via `genvar` |
| `pe.v` | Single Processing Element (PE) — multiply-accumulate unit |
| `firmware/firmware.S` | RV32IM assembly firmware driving the accelerator from software |
| `firmware/link.ld` | Linker script placing firmware at address 0x0 |
| `sim/firmware.hex` | Assembled firmware image, one 32-bit word per line, for `$readmemh` |
| `sim/tb_soc.sv` | Full-SoC testbench (CPU + memory + AXI + accelerator, end to end) |
| `sim/tb_systolic.sv` | Earlier testbench exercising only the AXI interface + accelerator in isolation |

---

## Address Map

| Address | Register | Description |
|---|---|---|
| `0x0000_0000 – 0x0000_0FFF` | Program/Data RAM | 4KB instruction + data memory |
| `0x8000_0000` | Control | Bit 0 = `load_weight` |
| `0x8000_0004` | Weights | Packed weight data for the left column |
| `0x8000_0008` | Activations | Packed activation data for the top row |
| `0x8000_0010` | LED / GPIO | Output register, low byte drives board LEDs |
| `0x8000_0020 / 24 / 28 / 2C` | Result readback | 16-bit accumulated output per PE, one address each |

---

## How It Works

### Processing Element (`pe.v`)
Each PE implements a **weight-stationary** dataflow:
1. **Load phase** (`load_weight = 1`): The PE latches `weight_in` into a local register and freezes it.
2. **Compute phase** (`load_weight = 0`): Every clock cycle, the PE multiplies the incoming activation by its stationary weight and accumulates the result, propagating data to the right (weights) and downward (activations) for the next PE in the grid.

The accumulator is double-width (`2 * DATA_WIDTH`) to prevent overflow.

**Known limitation:** the accumulator has no single-shot/stop mode — as long as `load_weight` is low and the activation input is held steady, it keeps accumulating every cycle. This means the result read back depends on exactly how many cycles elapsed between the activation write and the read, rather than a deterministic single MAC result. Worth addressing (e.g. a `start`/`done` pulse) before treating this as a finished accelerator design.

### Systolic Array (`systolic_array.v`)
A `GRID_SIZE × GRID_SIZE` grid of PEs generated via nested `genvar` loops. Default configuration: **2×2 array**, **8-bit data**, **16-bit** accumulated outputs.

### AXI4-Lite Interface (`axi_interface.v`)
A 3-state FSM (`IDLE → WRITE → RESP`) handles AXI4-Lite writes. Internally decodes local offsets `0x0/0x4/0x8`; `soc_top.v` translates the CPU's peripheral-space addresses (`0x8000_00xx`) down to these offsets before handing them to this module.

### SoC Top (`soc_top.v`)
Instantiates program memory, the PicoRV32 core, the AXI-mapped accelerator, and an LED/result-readback register, all arbitrated by address decode on the CPU's single memory bus. PicoRV32 is configured with **MUL enabled**, **DIV disabled**.

---

## Verified Result

Firmware (`firmware/firmware.S`) runs on the CPU and performs the same sequence as the original standalone accelerator test — load weight `0x0402`, freeze it, stream activation `0x0306`, wait for the pipeline, read back PE[0][0]'s result, and write it to the LED register.

Confirmed matching across two independent simulators:
--- FULL SoC SIMULATION RESULT ---
LED register value : 160 (0xa0)

(Icarus Verilog and Vivado XSim behavioral simulation, same firmware image, same result.)

---

## Configuration Parameters

| Parameter | Default | Description |
|---|---|---|
| `GRID_SIZE` | `2` | Width/height of the systolic array (NxN) |
| `DATA_WIDTH` | `8` | Bit-width of weights and activations |

To scale up to a 4×4 array, change `GRID_SIZE` to `4` in the `soc_top.v` instantiations of `axi_interface` and `systolic_array` (note: the LED/AXI data-path widths are currently sized for `GRID_SIZE=2` and would need widening too).

---

## Running the Simulation

**Icarus Verilog:**
```bash
cd sim
iverilog -g2012 -o full_soc_sim.vvp ../rtl/soc_top.v ../rtl/picorv32.v \
    ../rtl/mem.v ../rtl/axi_interface.v ../rtl/systolic_array.v ../rtl/pe.v tb_soc.sv
vvp full_soc_sim.vvp
```

**Vivado (behavioral simulation):**
Add all `rtl/*.v` files as Design Sources, `sim/tb_soc.sv` as a Simulation Source (set as top), and `sim/firmware.hex` as a Design Source (needed by both synthesis and simulation via `mem.v`'s `$readmemh`). Run **Flow Navigator → Run Simulation → Run Behavioral Simulation**, then `run all` in the Tcl console.

To view waveforms in Icarus output: `gtkwave dump_soc.vcd`

### Rebuilding the firmware image
```bash
riscv64-linux-gnu-as -march=rv32im -mabi=ilp32 -o firmware.o firmware/firmware.S
riscv64-linux-gnu-ld -m elf32lriscv -T firmware/link.ld -o firmware.elf firmware.o
riscv64-linux-gnu-objcopy -O binary firmware.elf firmware.bin
```
Then convert the raw binary to one 32-bit hex word per line for `$readmemh` (see `firmware/` for the conversion script/notes).

---

## Dependencies

- [Icarus Verilog](https://steveicarus.github.io/iverilog/) — simulation
- [Vivado](https://www.xilinx.com/support/download.html) — synthesis, implementation, alternate simulation
- [GTKWave](http://gtkwave.sourceforge.net/) — waveform viewing (optional)
- [PicoRV32](https://github.com/YosysHQ/picorv32) — open-source RISC-V core used as the CPU
- `riscv64-linux-gnu-gcc`/`as`/`ld`/`objcopy` (or an RV32 bare-metal toolchain) — for building firmware

---

## Next Steps

- Add XDC timing/pin constraints for target board (Spartan-7 XC7S50CSGA324-1)
- Run synthesis/implementation, confirm BRAM inference for `mem.v` and timing closure
- Hardware bring-up and physical verification once board access is available
- Fix accelerator's continuous-accumulation behavior with a proper single-shot compute mode
