# CPU Tiny Tapeout — design log

Educational 8-bit CPU in SystemVerilog, single shared bus, SAP-style
architecture. Target: submit it to the Tiny Tapeout IHP 26b shuttle
(closes 2026-09-21).

This document is a running log of the state and decisions made so far.
It lives at the repo root of `ttihp-verilog-template`: `DESIGN.md`.

## File structure

```
ttihp-verilog-template/
├── info.yaml                  Tiny Tapeout project metadata (required for submission)
├── src/                       everything Tiny Tapeout's synthesis flow reads, per info.yaml's source_files
│   ├── tt_um_tiarinix_ttihp_verilog_template.sv   TT wrapper (top_module)
│   ├── CPU.sv                 CPU top-level module, wires everything together
│   └── modules/
│       ├── alu.sv                8-bit ALU, 8 operations
│       ├── control.sv            control unit (FSM + decoder)
│       ├── memory.sv             program/data memory (Von Neumann)
│       ├── mux.sv                generic parameterized mux (N inputs)
│       ├── plus_one_adder.sv     combinational incrementer for the PC
│       ├── register.sv           generic WIDTH-bit register
│       └── tristate_buffer.sv    tri-state buffer for the shared bus
├── testbench/
│   ├── CPU_tb.sv              main testbench (drives CPU.sv directly)
│   └── tt_wrapper_tb.sv       testbench through the TT wrapper's pinout
├── unit_tests/                 one self-contained testbench per instruction
│                               (see "Per-instruction individual tests" below).
│                               Deliberately named `unit_tests/`, not `test/`,
│                               to avoid colliding with Tiny Tapeout's own
│                               `test/` (the cocotb harness: `test/Makefile` +
│                               `test/tb.v` + `test/test.py`, which the
│                               ttihp-verilog-template already ships and CI
│                               (`test.yaml`) actually runs).
├── test/                       Tiny Tapeout's official cocotb harness
│                               (Makefile, tb.v, test.py, requirements.txt) —
│                               this is what test.yaml runs in CI.
└── DESIGN.md                  this file
```

**No `` `include `` anywhere in `src/`.** Every file under `src/` is a
standalone compilation unit, listed explicitly both in `info.yaml`'s
`source_files` and in `test/Makefile`'s `PROJECT_SOURCES` and
`unit_tests/run_all.sh`'s compile command. This mirrors exactly how Tiny
Tapeout's synthesis flow consumes a multi-file design (it reads each listed
file directly, it doesn't run a preprocessor `` `include `` chain from a
single entry point) — so there's no divergence between "how we simulate
locally" and "how it actually gets built".

## Architecture

- One shared 8-bit bus across all blocks (`bus` in `CPU.sv`).
- Single memory for program and data (Von Neumann), depth parameterized
  via `MEM_DEPTH` (default 16; the current testbench instantiates it with
  64 to have room for addresses).
- 4-state instruction cycle in `control.sv`:
  1. `FETCH1`  — `IR <- mem[PC]`, `PC <- PC+1`
  2. `FETCH2`  — only for instructions with an operand: reads the second
     byte and routes it to `ADDR` (or straight to `PC` if it's a jump)
  3. `EXECUTE` — decodes `IR` and triggers the operation (ALU, etc.)
  4. `STORE`   — memory access or register write, when applicable
- The `ADDR` register is always loaded from the bus (no mux of its own).
  The real mux is **after** it: `mem_addr_sel` picks whether `MEM.Addr`
  comes from `ADDR` or straight from `PC`.
- 5 general-purpose registers (A-E). `CONTROL` doesn't expose a `wr` per
  register: it exposes `reg_dest_sel[2:0]` + `reg_dest_wr`, and `CPU.sv`
  decodes the per-register enable right there. Same pattern already used
  by `alu_sel_a/b` and `bus_out_sel` (a 3-bit selector into an N-input
  mux) — scales to 5 registers without adding ports.
- During `program_mode` (flashing), `external_input` writes directly to
  `MEM.In` and `MEM.Addr` is forced to `PC`, bypassing both the bus and
  `ADDR` — it's a path separate from the normal datapath.
- `halted` (in `CPU.sv`) permanently freezes `cpu_clk`/`mem_pc_clk` once
  `HLT` executes, until the next `reset`.

## Bugs found and fixed (debugging session)

1. **`tristate_buffer.sv`: `output logic` instead of `output wire`.**
   In SystemVerilog, `logic` on an output port behaves like a variable
   (only one driver allowed). With 5 tri-state buffers driving the same
   `bus`, Icarus failed with "must have a single driver". Changed to
   `output wire` (a net, which allows multiple drivers with high-impedance
   resolution).

2. **`memory.sv`: `reset` was clearing all of memory's contents.**
   The testbench does a second `reset` after flashing the program (to
   bring the PC back to 0), and that was wiping the program that had just
   been loaded. Memory-clearing on reset was removed — real program memory
   isn't cleared by the CPU's reset, only the datapath registers are.

3. **Race condition releasing `reset` in the testbench.**
   The pattern `reset = 1; repeat(2) @(posedge clk); reset = 0;` dropped
   reset on the exact same edge the FSM uses to decide its transition,
   which in simulation is a race between two concurrent processes. A `#1;`
   was added before dropping `reset` so the change lands away from any
   edge.

4. **`needs_operand` badly synchronized in `control.sv`.**
   The decision of whether `FETCH2` is needed read `bus_in` live, but by
   the time that signal was evaluated the PC had already been incremented
   (within the same `FETCH1` state) and the bus was already showing the
   byte after the opcode. Changed to use `ir_out` instead (already loaded
   half a cycle earlier, at no extra cost), and removed the `bus_in` port
   which was no longer needed.

5. **`register.sv`/`memory.sv`: blocking (`=`) instead of non-blocking
   (`<=`) assignment inside `always_ff`.** Functionally equivalent for
   these specific single-assignment blocks, but non-blocking is the
   correct style for sequential logic and avoids a lint warning some
   tools raise. Fixed when integrating into `ttihp-verilog-template`.

## Instruction set — history

**Implemented before this section's redesign:**
`NOP, LDA, LDB, ADD, OUT, STR, JMP, HLT` — 3 registers (A, B, C), no
conditional jumps, no usable external input (the `Reg IN` datapath exists
but no opcode triggered it), flags (`FLAGS`) wired but never updated by
any instruction.

## Instruction set — final (IMPLEMENTED)

Adds registers D and E (5 total, matching the original block diagram),
conditional jumps, and the `IN` instruction for external input. Format:
family = `ir_out[7:3]`, register/condition field = `ir_out[2:0]`.
Registers: A=000, B=001, C=010, D=011, E=100 (101-111 invalid → fall into
the "unknown instruction" `default`).

| Opcode | Mnemonic | Bytes | Effect |
|---|---|---|---|
| `0x00` | `NOP` | 1 | nothing |
| `0x08-0x0C` | `LD reg, addr` | 2 | `reg <- mem[addr]` |
| `0x10-0x14` | `ST reg, addr` | 2 | `mem[addr] <- reg` |
| `0x18-0x1C` | `ADD reg` | 1 | `A <- A + reg` |
| `0x20-0x24` | `SUB reg` | 1 | `A <- A - reg` |
| `0x28-0x2C` | `AND reg` | 1 | `A <- A & reg` |
| `0x30-0x34` | `OR reg` | 1 | `A <- A \| reg` |
| `0x38-0x3C` | `XOR reg` | 1 | `A <- A ^ reg` |
| `0x40-0x44` | `OUT reg` | 1 | `external_output <- reg` |
| `0x48-0x4C` | `IN reg` | 1 | `reg <- external_input` |
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
| `0x60-0x64` | `CMP reg` | 1 | `flags <- A - reg` (A untouched) |
| `0xFF` | `HLT` | 1 | stops the CPU |

**Design decisions:**
- Accumulator-style ALU: every ALU operation is `A <- A OP reg`, it never
  writes to another destination register. Avoids needing a second
  "destination register" field per opcode.
- `CMP` reuses `SUB`'s path (same `alu_op`, same `reg_f_wr=1`) but doesn't
  do `alu_out_en`/`reg_dest_wr` in `STORE` — the result is discarded, only
  the flags remain.
- Every instruction in the ALU family
  (`ADD/SUB/AND/OR/XOR/NOT/SHL/SHR/CMP`) sets `reg_f_wr=1` in `EXECUTE`, so
  conditional jumps have real data to evaluate.
- `IN` reuses the existing `reg_ext_in` → tristate → bus path: in
  `EXECUTE` it does `ext_in_wr=1` (captures `external_input`), in `STORE`
  it does `ext_in_en=1` + writing the destination register (same pattern
  `STORE` uses for everything else).
- Conditional jumps resolve in `FETCH2`, just like `JMP` already did
  before (without adding new states): if the condition isn't met, it
  simply does `PC <- PC+1` instead of `PC <- bus`.

**Implementation:** `modules/control.sv` decodes `family = ir_out[7:3]`
and `field = ir_out[2:0]` (register or condition, depending on the
family). The destination register no longer has one `wr` per letter:
`CONTROL` exposes `reg_dest_sel[2:0]` + `reg_dest_wr`, decoded in
`CPU.sv` into the 5 individual enables.

## Block diagram — differences from the current RTL

(still pending being redrawn)

1. The diagram already showed 5 registers (A-E) — the RTL now has them
   too, this difference is closed.
2. The `ADDR` mux is drawn **before** the register; in the real RTL it's
   **after** (between the `ADDR`/`PC` output and `MEM.Addr`).
3. Missing the flashing bypass path (`external_input` → `MEM.In` direct,
   `PC` → `MEM.Addr` direct during `program_mode`).
4. Missing the `FLAGS → CONTROL` feedback line (already in the RTL, and
   now it's actually used, by the conditional jumps).

## Tiny Tapeout wrapper (IMPLEMENTED)

`src/tt_um_tiarinix_ttihp_verilog_template.sv` adapts TT's fixed pinout
to `CPU.sv`'s own port, without touching the datapath:

| TT | CPU.sv | Note |
|---|---|---|
| `clk` | `clk` | direct |
| `rst_n` (active low) | `reset` (active high) | `wire reset = ~rst_n;` |
| `ui_in[7:0]` | `external_input` | direct, 8 dedicated pins |
| `uo_out[7:0]` | `external_output` | direct, 8 dedicated pins |
| `uio_in[0]` | `program_mode` | from the bidirectional pins, as input |
| `uio_in[1]` | `program_wr` | same |
| `uio_out`, `uio_oe` | — | fixed at `8'h00` (no bidirectional outputs used) |
| `ena` | — | unused, grouped into an `_unused` wire together with `uio_in[7:2]` so the linter doesn't complain |

Verified with `testbench/tt_wrapper_tb.sv` (a minimal 16-word program,
the same `MEM_DEPTH` the production wrapper uses): `PASS: uo_out = 8`.
Deliberately confirmed that inverting `rst_n` actually matters (tested
with `reset = rst_n` without inverting, got `FAIL: uo_out = 0`, then
restored).

**Timing detail worth keeping in mind:** the first attempt at this
testbench failed because it changed `program_wr`/`ui_in` at the exact
same clock edge that consumes them (same pattern already used by
`testbench/CPU_tb.sv` with the CPU wired directly). Going through one
extra level of hierarchy (bit-select → wrapper port → CPU port) needs
more propagation margin than that pattern leaves. Fixed by setting the
values mid-cycle (right after a `posedge`) instead of exactly on the
`negedge` that consumes them. It's not a bug in the wrapper, it's
testbench stimulus timing — but worth keeping in mind if more testbenches
are added that drive signals through the wrapper.

## `info.yaml` (IMPLEMENTED)

Filled in at the repo root against the `ttihp-verilog-template` schema.
Notable choices:
- `language: "SystemVerilog"` (the source uses `logic`, `always_comb`,
  `always_ff`, not plain Verilog). LibreLane's Yosys synthesis step reads
  Verilog files with `-sv` by default, so this subset (no interfaces,
  packages, or other advanced SV features) synthesizes without extra
  configuration.
- `clock_hz: 0` — honest placeholder, since there's been no timing closure
  against a target frequency yet (see the synthesis-check pending item).
- `tiles: "1x1"` — default, unvalidated against real area (same caveat).
- `pinout` documents the mapping already described in the wrapper section
  above (`ui[0..7]` → `external_input`, `uo[0..7]` → `external_output`,
  `uio[0]`/`uio[1]` → `program_mode`/`program_wr`, rest of `uio` blank).
- `source_files` lists every file under `src/` explicitly, matching
  `test/Makefile`'s `PROJECT_SOURCES`.

## Pending for the Tiny Tapeout submission

1. **Shuttle deadline.** Targeting TTIHP26b, which closes 2026-09-21.
2. **Real cocotb test in `test/test.py`.** The official harness currently
   still runs the generic example test (`assert True`) — it compiles and
   "passes" but doesn't exercise the CPU. `unit_tests/` and
   `testbench/tt_wrapper_tb.sv` already prove the design works; porting
   one of those programs into `test/test.py` (driving the wrapper's real
   pins: `rst_n`, `uio_in[0:1]`, `ui_in`) is what's left to make the
   official CI test — and the automatic gate-level test that `gds.yaml`
   runs on the post-synthesis netlist — actually meaningful.
3. **Synthesis check** (Yosys/LibreLane) — never run against the real IHP
   PDK yet; there are Icarus warnings (`sel` port widths on the muxes, a
   "sorry" in `alu.sv` about constant selects) that could be real
   synthesis problems even though they simulate fine. Also unconfirmed:
   whether the design actually fits in `tiles: "1x1"`.
4. Redraw the block diagram (see the previous section).

## Verification status

`testbench/CPU_tb.sv` was rewritten for the final instruction set and
passes: `PASS: external_output = 255 (expected 255)`. In a single program
it exercises: `LD/ST` (with a memory roundtrip), `ADD/SUB/AND/OR/XOR/NOT/
SHR/SHL`, `CMP` (via `SUB`+flags), `JZ` and `JNZ` (with traps that corrupt
the result to `99` if the jump fails in either direction — jumps when it
shouldn't, or doesn't jump when it should), and `IN`/`OUT` with registers
D and E in addition to A/B/C.

Verified that the traps are real (not false positives): `JZ` was broken
on purpose (forced to never jump) and gave `FAIL: 99` as expected; `JNZ`
was broken on purpose (forced to always jump) and also gave `FAIL: 99`.
Both cases restored before leaving the final run green.

## Per-instruction individual tests

`unit_tests/` has one file per instruction (22 total: `test_nop.sv`,
`test_ld.sv`, `test_st.sv`, `test_add.sv`, `test_sub.sv`, `test_and.sv`,
`test_or.sv`, `test_xor.sv`, `test_out.sv`, `test_in.sv`, `test_jmp.sv`,
`test_jz.sv`, `test_jnz.sv`, `test_jc.sv`, `test_jnc.sv`, `test_jn.sv`,
`test_jo.sv`, `test_not.sv`, `test_shl.sv`, `test_shr.sv`, `test_cmp.sv`,
`test_hlt.sv`), each self-contained: it instantiates `CPU` directly
(without going through the TT wrapper), with its own minimal program and
its own `PASS`/`FAIL`. `unit_tests/run_all.sh` compiles and runs all of
them and prints a summary (`./unit_tests/run_all.sh` from the root).
Current status: **22/22 PASS**.

Conditional jumps (`JZ/JNZ/JC/JNC/JN/JO`) each use their own trap (same as
`JMP` and `CMP`): if the jump doesn't do what it's supposed to, the result
falls into a "bad" value (99) instead of the expected one (42). Verified
that `JC` (previously without dedicated verification) actually catches
breakage — forced `jump_taken=0` for that condition, got
`FAIL: external_output = 99` as expected, and restored it. `JNC/JN/JO`
share the same mechanism/`case` as `JC`, so they're covered by the same
kind of trap even though they weren't individually broken one by one.
