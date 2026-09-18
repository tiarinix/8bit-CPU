![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 8-bit Educational SAP-style CPU

A small, from-scratch 8-bit CPU built for [Tiny Tapeout](https://tinytapeout.com) — a single
shared bus, 5 general-purpose registers, an 8-operation ALU, conditional jumps, and
byte-programmable Von Neumann memory, hardened for the IHP SG13G2 (130nm) open PDK.

- [Datasheet / project docs](docs/info.md)
- [Design log (architecture, debugging history, verification notes)](DESIGN.md)

## Overview

| | |
|---|---|
| Architecture | SAP-style (Simple-As-Possible), single shared 8-bit bus, Von Neumann (shared program/data memory) |
| Registers | 5 general-purpose (A–E) + flags (carry/negative/zero/overflow) + PC + IR + ADDR |
| ALU | 8 operations: ADD, SUB, AND, OR, XOR, NOT, SHL, SHR |
| Instructions | 23 opcodes, 1–2 bytes each (see [Instruction set](#instruction-set)) |
| Memory | 14 bytes, byte-addressable, programmed live over the chip's I/O pins |
| Process | IHP SG13G2 (130nm BiCMOS open PDK), 1×1 Tiny Tapeout tile (~167×108 µm) |
| Language | SystemVerilog |

## Architecture

Every functional block reads from and writes to one shared 8-bit `bus` in `CPU.sv`; only one
source drives it at a time, selected combinationally by an enable per source (no tri-state
internal to the design). Instructions execute in up to 4 cycles, decoded by the FSM in
[`modules/control.sv`](src/modules/control.sv):

1. **FETCH1** — `IR <- mem[PC]`, `PC <- PC + 1`
2. **FETCH2** — only for 2-byte instructions: reads the operand byte, routes it to `ADDR`
   (or straight to `PC` for a taken jump)
3. **EXECUTE** — decodes `IR` and drives the ALU / control signals for this opcode
4. **STORE** — writes the result to memory or to a register, when the opcode needs it

Program and data share the same memory (Von Neumann) — there's no separate instruction/data
address space. The CPU is flashed by holding `program_mode` high and pulsing `program_wr`
once per byte; while flashing, `external_input` writes directly into memory at the current
`PC`, bypassing the normal datapath entirely.

## Instruction set

Opcode = `family (ir_out[7:3])` + `register or condition field (ir_out[2:0])`.
Registers: A=000, B=001, C=010, D=011, E=100.

| Opcode | Mnemonic | Bytes | Effect |
|---|---|---|---|
| `0x00` | `NOP` | 1 | nothing |
| `0x08–0x0C` | `LD reg, addr` | 2 | `reg <- mem[addr]` |
| `0x10–0x14` | `ST reg, addr` | 2 | `mem[addr] <- reg` |
| `0x18–0x1C` | `ADD reg` | 1 | `A <- A + reg` |
| `0x20–0x24` | `SUB reg` | 1 | `A <- A - reg` |
| `0x28–0x2C` | `AND reg` | 1 | `A <- A & reg` |
| `0x30–0x34` | `OR reg` | 1 | `A <- A \| reg` |
| `0x38–0x3C` | `XOR reg` | 1 | `A <- A ^ reg` |
| `0x40–0x44` | `OUT reg` | 1 | `external_output <- reg` |
| `0x48–0x4C` | `IN reg` | 1 | `reg <- external_input` |
| `0x50` | `JMP addr` | 2 | `PC <- addr` (unconditional) |
| `0x51` | `JZ addr` | 2 | jumps if `zero` |
| `0x52` | `JNZ addr` | 2 | jumps if `~zero` |
| `0x53` | `JC addr` | 2 | jumps if `carry` |
| `0x54` | `JNC addr` | 2 | jumps if `~carry` |
| `0x55` | `JN addr` | 2 | jumps if `negative` |
| `0x56` | `JO addr` | 2 | jumps if `overflow` |
| `0x58` | `NOT` | 1 | `A <- ~A` |
| `0x59` | `SHL` | 1 | `A <- A << 1` |
| `0x5A` | `SHR` | 1 | `A <- A >> 1` |
| `0x60–0x64` | `CMP reg` | 1 | `flags <- A - reg` (A untouched) |
| `0xFF` | `HLT` | 1 | stops the CPU until reset |

`ADD/SUB/AND/OR/XOR/NOT/SHL/SHR/CMP` always update the flags register, so conditional jumps
always have current data to evaluate.

## Pinout

| TT pin | Signal | Direction |
|---|---|---|
| `ui[0:7]` | `external_input[0:7]` | in — `IN` opcode target |
| `uo[0:7]` | `external_output[0:7]` | out — `OUT` opcode target |
| `uio[0]` | `program_mode` | in — hold high to flash a program |
| `uio[1]` | `program_wr` | in — pulse once per byte while flashing |
| `uio[2:7]` | unused | — |
| `rst_n` | active-low reset | in — CPU reset (`reset = ~rst_n` internally) |

## How to test

1. Hold `rst_n` low for at least 2 clock cycles, then release it.
2. Flash a program: set `uio_in[0]` (`program_mode`) high, then for each program byte set
   `ui_in` to the byte value and pulse `uio_in[1]` (`program_wr`) for one clock cycle.
3. Drop `program_mode` and pulse `rst_n` again so the PC returns to `0` before execution
   starts.
4. Watch `uo_out` for `OUT` results, or drive `ui_in` before an `IN` executes.

See [`test/test.py`](test/test.py) for a working cocotb example (5 programs exercising
load/store, arithmetic, conditional jumps, `HLT`, and external I/O through the real Tiny
Tapeout pinout) — this is what CI (`test.yaml`) runs on every push.

## Repository layout

```
├── info.yaml                                    Tiny Tapeout project metadata
├── src/                                          everything the synthesis flow reads
│   ├── tt_um_tiarinix_ttihp_verilog_template.sv    top module: adapts the TT pinout to CPU.sv
│   ├── CPU.sv                                      CPU top level, wires every block together
│   └── modules/
│       ├── alu.sv                8-bit ALU, 8 operations
│       ├── control.sv            control unit (FSM + instruction decoder)
│       ├── memory.sv             program/data memory (Von Neumann)
│       ├── mux.sv                generic parameterized N-input mux
│       ├── plus_one_adder.sv     combinational incrementer for the PC
│       └── register.sv           generic WIDTH-bit register
├── test/                                         Tiny Tapeout's cocotb harness (test.yaml runs this)
├── testbench/                                    standalone SystemVerilog testbenches
├── unit_tests/                                   one self-contained testbench per instruction (22 total)
├── docs/info.md                                  datasheet source (rendered by the docs workflow)
└── DESIGN.md                                     design log: decisions, bugs found, verification history
```

## Building and testing locally

- **Official cocotb harness** (what CI runs): `cd test && make` (needs `iverilog` and
  `cocotb` — see [test/README.md](test/README.md)).
- **Per-instruction unit tests** (Icarus, no cocotb needed): `./unit_tests/run_all.sh` —
  currently 22/22 passing.
- **Full chip hardening** (Yosys + OpenROAD/LibreLane against the real IHP SG13G2 PDK):
  see [Tiny Tapeout's local hardening guide](https://www.tinytapeout.com/guides/local-hardening/),
  or just push — `gds.yaml` runs the same flow in CI.

## Physical implementation notes

- **Tile:** `1×1` (~167×108 µm). The memory array is synthesized as individual standard-cell
  flip-flops (no SRAM macro — the PDK's real SRAM macros are fixed at 1024 words minimum,
  far too large for this tile), so its size trades directly against area.
- **`MEM_DEPTH = 14`** bytes is the largest memory that fits this tile with clean timing
  closure; 16 hits a placement-legalization wall during CTS even after every other knob
  (floorplan margins, target density) is tuned. See [DESIGN.md](DESIGN.md) for the full
  investigation.
- **Reset:** synchronous everywhere (registers, the control FSM, and the halt flag all reset
  on the same clock edge) — deliberately not mixed sync/async, to keep the reset tree simple
  for CTS/STA.
- **Clocking:** a single real clock drives every flip-flop. Freezing the datapath on `HLT`
  or during flashing is done with synchronous write-enables, not by gating the clock signal
  itself — gating the clock split it into two derived clock trees with no declared
  relationship in the SDC, which showed up as an unfixable ~10ns hold violation before this
  was reworked.

## What is Tiny Tapeout?

[Tiny Tapeout](https://tinytapeout.com) is an educational project that makes it cheap and
easy to get real digital (and analog) designs manufactured on an actual chip. The GitHub
Actions in this repo automatically build the ASIC files using
[LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/) and run this project's
tests on every push.

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)
