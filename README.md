# RISC-V SoC with Systolic Array ML Accelerator

A custom System-on-Chip (SoC) implemented in Verilog, integrating a **PicoRV32 RISC-V CPU** with a **weight-stationary systolic array** for hardware-accelerated matrix multiplication. The CPU communicates with the accelerator over an AXI4-Lite bus.

---

## Architecture Overview

```
┌───────────────────────────────────────────────────┐
│                    soc_top                        │
│                                                   │
│  ┌─────────────┐     ┌───────────────────────┐   │
│  │  PicoRV32   │     │    axi_interface       │   │
│  │  RISC-V CPU │────▶│  (AXI4-Lite Slave FSM)│   │
│  │  (Master)   │     └──────────┬────────────┘   │
│  └─────────────┘                │                 │
│                                 ▼                 │
│                       ┌─────────────────┐         │
│                       │  systolic_array │         │
│                       │   (NxN grid of  │         │
│                       │      PEs)       │         │
│                       └─────────────────┘         │
└───────────────────────────────────────────────────┘
```

The CPU issues memory-mapped writes to program the accelerator. The AXI interface decodes these transactions and drives the systolic array with weights and activations.

---

## File Structure

| File | Description |
|---|---|
| `soc_top.v` | Top-level SoC module; instantiates and wires all components |
| `picorv32.v` | PicoRV32 RISC-V CPU core (open-source, third-party) |
| `axi_interface.v` | AXI4-Lite slave interface with address-decode FSM |
| `systolic_array.v` | Parameterized NxN systolic array, generated via `genvar` |
| `pe.v` | Single Processing Element (PE) — multiply-accumulate unit |
| `full_soc_sim.vvp` | Compiled simulation binary (Icarus Verilog) |

---

## How It Works

### Processing Element (`pe.v`)
Each PE implements a **weight-stationary** dataflow:
1. **Load phase** (`load_weight = 1`): The PE latches its `weight_in` into a local register and freezes it.
2. **Compute phase** (`load_weight = 0`): On every clock cycle, the PE multiplies the incoming activation by its stationary weight and accumulates the result. Data is also propagated to the right (weights) and downward (activations) for the next PE in the grid.

The accumulator is double-width (`2 * DATA_WIDTH`) to prevent overflow.

### Systolic Array (`systolic_array.v`)
A `GRID_SIZE × GRID_SIZE` grid of PEs is generated using nested `genvar` loops. Flat 1D input buses are unpacked into the 2D wire mesh at the boundaries, and outputs are re-packed into a flat bus. The default configuration is a **2×2 array** with **8-bit data**, producing **16-bit** accumulated outputs.

### AXI4-Lite Interface (`axi_interface.v`)
A 3-state FSM (`IDLE → WRITE → RESP`) handles the AXI4-Lite write protocol. The CPU programs the accelerator via three memory-mapped registers:

| Address | Register | Description |
|---|---|---|
| `0x0000_0000` | Control | Bit 0 = `load_weight` signal |
| `0x0000_0004` | Weights | Packed weight data for the left column |
| `0x0000_0008` | Activations | Packed activation data for the top row |

### SoC Top (`soc_top.v`)
Connects the PicoRV32 memory bus directly to the AXI slave interface. The CPU's `mem_valid` + `mem_wstrb` signals are decoded to drive the AXI write channels. The PicoRV32 is configured with the **MUL extension enabled** and **DIV disabled**.

---

## Configuration Parameters

| Parameter | Default | Description |
|---|---|---|
| `GRID_SIZE` | `2` | Width/height of the systolic array (NxN) |
| `DATA_WIDTH` | `8` | Bit-width of weights and activations |

To scale up to a 4×4 array, change `GRID_SIZE` to `4` in the `soc_top.v` instantiation.

---

## Running the Simulation

The repo includes a pre-compiled simulation binary. Run it directly with:

```bash
vvp full_soc_sim.vvp
```

To recompile from source (requires [Icarus Verilog](https://steveicarus.github.io/iverilog/)):

```bash
iverilog -o full_soc_sim.vvp soc_top.v picorv32.v axi_interface.v systolic_array.v pe.v <your_testbench>.v
vvp full_soc_sim.vvp
```

To view waveforms, add `$dumpfile`/`$dumpvars` to your testbench and open the output with [GTKWave](http://gtkwave.sourceforge.net/):

```bash
gtkwave dump.vcd
```

---

## Dependencies

- [Icarus Verilog](https://steveicarus.github.io/iverilog/) — for simulation
- [GTKWave](http://gtkwave.sourceforge.net/) — for waveform viewing (optional)
- [PicoRV32](https://github.com/YosysHQ/picorv32) — the open-source RISC-V core used as the CPU

---

