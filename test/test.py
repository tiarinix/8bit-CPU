# SPDX-FileCopyrightText: © 2026 Tiara Ramirez
# SPDX-License-Identifier: Apache-2.0
#
# Drives the CPU through the real Tiny Tapeout pinout (ui_in / uo_out /
# uio_in / rst_n), the same wrapper that gets hardened and shipped. Every
# program here is hand-verified against the standalone SystemVerilog
# testbenches (testbench/tt_wrapper_tb.sv, testbench/CPU_tb.sv and the
# 22 unit_tests/test_*.sv), just re-addressed to fit the production
# MEM_DEPTH=16 instead of the larger depth those use for convenience.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, Timer

PROGRAM_MODE = 1 << 0
PROGRAM_WR = 1 << 1


async def start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 2)
    await Timer(1, unit="ns")  # release away from the edge the FSM samples
    dut.rst_n.value = 1


async def flash_program(dut, program):
    """Loads `program` (a list of bytes) into memory via program_mode/program_wr,
    then resets so the PC goes back to 0 before execution starts. Mirrors the
    exact bit-timing verified in testbench/tt_wrapper_tb.sv: values are set
    mid-cycle (right after a posedge), not at the edge that consumes them --
    going through the wrapper needs that extra propagation margin.
    """
    dut.uio_in.value = PROGRAM_MODE
    for byte in program:
        await RisingEdge(dut.clk)
        dut.ui_in.value = byte
        dut.uio_in.value = PROGRAM_MODE | PROGRAM_WR
        await FallingEdge(dut.clk)
        dut.uio_in.value = PROGRAM_MODE
    dut.uio_in.value = 0
    dut.ui_in.value = 0

    await reset(dut)


@cocotb.test()
async def test_load_add_out(dut):
    """LD A / LD B / ADD B / OUT A / HLT -- same program verified by
    testbench/tt_wrapper_tb.sv. A=5, B=3, A+B=8."""
    await start_clock(dut)
    await reset(dut)

    program = [0] * 16
    program[0], program[1] = 0x08, 14  # LD A,#14 (data 5)
    program[2], program[3] = 0x09, 15  # LD B,#15 (data 3)
    program[4] = 0x19                  # ADD B    -> A = 5+3 = 8
    program[5] = 0x40                  # OUT A
    program[6] = 0xFF                  # HLT
    program[14] = 5
    program[15] = 3

    await flash_program(dut, program)
    await ClockCycles(dut.clk, 60)

    assert dut.uo_out.value == 8, f"expected uo_out=8, got {int(dut.uo_out.value)}"


@cocotb.test()
async def test_store_load_roundtrip(dut):
    """ST A,#addr then LD B,#addr -- proves memory is actually read/written,
    not just wired through. A=7, stored, read back into B, output 7."""
    await start_clock(dut)
    await reset(dut)

    program = [0] * 16
    program[0], program[1] = 0x08, 8   # LD A,#8  (data 7)
    program[2], program[3] = 0x10, 9   # ST A,#9  (scratch)
    program[4], program[5] = 0x09, 9   # LD B,#9  (re-read what ST just wrote)
    program[6] = 0x41                  # OUT B
    program[7] = 0xFF                  # HLT
    program[8] = 7
    program[9] = 0  # placeholder, overwritten by ST

    await flash_program(dut, program)
    await ClockCycles(dut.clk, 60)

    assert dut.uo_out.value == 7, f"expected uo_out=7, got {int(dut.uo_out.value)}"


@cocotb.test()
async def test_conditional_jump_jz(dut):
    """SUB A (A-A=0, zero=1) then JZ -- verifies flags actually feed back into
    the jump decision. Trap at the fall-through path corrupts the result to
    99 if JZ fails to jump; the correct path gives 42."""
    await start_clock(dut)
    await reset(dut)

    program = [0] * 16
    program[0], program[1] = 0x08, 13  # LD A,#13   A=5
    program[2] = 0x20                  # SUB A      A=0, zero=1
    program[3], program[4] = 0x51, 9   # JZ #9      should jump
    program[5], program[6] = 0x08, 14  # TRAP: LD A,#14 (bad=99)
    program[7] = 0x40                  # OUT A
    program[8] = 0xFF                  # HLT
    program[9], program[10] = 0x08, 15  # CORRECT: LD A,#15 (good=42)
    program[11] = 0x40                 # OUT A
    program[12] = 0xFF                 # HLT
    program[13] = 5
    program[14] = 99
    program[15] = 42

    await flash_program(dut, program)
    await ClockCycles(dut.clk, 60)

    assert dut.uo_out.value == 42, f"expected uo_out=42, got {int(dut.uo_out.value)}"


@cocotb.test()
async def test_halt_stops_cpu(dut):
    """HLT must actually freeze the CPU. Trap: if it doesn't, execution falls
    through to a second load that would overwrite the output with 99."""
    await start_clock(dut)
    await reset(dut)

    program = [0] * 16
    program[0], program[1] = 0x08, 10  # LD A,#10   A=55
    program[2] = 0x40                  # OUT A      output=55
    program[3] = 0xFF                  # HLT
    program[4], program[5] = 0x08, 11  # TRAP (should never execute): LD A,#11 (bad=99)
    program[6] = 0x40                  # OUT A
    program[7] = 0xFF                  # HLT
    program[10] = 55
    program[11] = 99

    await flash_program(dut, program)
    await ClockCycles(dut.clk, 60)

    assert dut.uo_out.value == 55, f"expected uo_out=55, got {int(dut.uo_out.value)}"


@cocotb.test()
async def test_external_input(dut):
    """IN A -- captures external_input (ui_in) through the wrapper's dedicated
    input pins, then OUT A puts it back out on uo_out."""
    await start_clock(dut)
    await reset(dut)

    program = [0] * 16
    program[0] = 0x48  # IN A
    program[1] = 0x40  # OUT A
    program[2] = 0xFF  # HLT

    await flash_program(dut, program)

    dut.ui_in.value = 123  # value IN will capture (ui_in is free once flashing is done)
    await ClockCycles(dut.clk, 60)

    assert dut.uo_out.value == 123, f"expected uo_out=123, got {int(dut.uo_out.value)}"
