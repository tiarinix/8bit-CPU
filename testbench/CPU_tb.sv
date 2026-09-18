`timescale 1ns/1ps

module CPU_tb;
    reg clk = 0;
    reg reset = 0;
    reg program_mode = 0;
    reg program_wr = 0;
    reg [7:0] external_input = 0;
    wire [7:0] external_output;

    // MEM_DEPTH=64 to have room for addresses in the test;
    // the default value (16) is still what's used for the real layout.
    CPU #(.MEM_DEPTH(64)) dut (
        .clk(clk),
        .reset(reset),
        .program_mode(program_mode),
        .program_wr(program_wr),
        .external_input(external_input),
        .external_output(external_output)
    );

    always #5 clk = ~clk; // 10ns period

    // Test program: exercises the definitive instruction set
    // (see DESIGN.md for the full opcode table).
    //
    //   addr0:  LD A,#5        A=5
    //   addr2:  LD B,#3        B=3
    //   addr4:  ADD B          A=5+3=8
    //   addr5:  ST A,#SCRATCH  mem[SCRATCH]=8
    //   addr7:  LD C,#SCRATCH  C=8 (re-reads what ST just stored)
    //   addr9:  SUB C          A=8-8=0, zero=1
    //   addr10: JZ #14         should jump (zero=1)
    //   addr12: JMP #40        TRAP: only reached if JZ didn't jump
    //   addr14: LD A,#0xF0     A=0xF0
    //   addr16: LD D,#0x0F     D=0x0F
    //   addr18: AND D          A=0xF0&0x0F=0x00, zero=1
    //   addr19: JNZ #40        TRAP: should not jump (zero=1 -> "not zero" is false)
    //   addr21: OR D           A=0x00|0x0F=0x0F
    //   addr22: XOR D          A=0x0F^0x0F=0x00
    //   addr23: NOT            A=~0x00=0xFF
    //   addr24: SHR            A=0xFF>>1=0x7F
    //   addr25: SHL            A=0x7F<<1=0xFE
    //   addr26: IN E           E <- external_input (=0x01, set by the testbench)
    //   addr27: ADD E          A=0xFE+0x01=0xFF
    //   addr28: OUT A          external_output <- 0xFF
    //   addr29: HLT
    //   addr40: LD A,#99       TRAP (destination of broken conditional jumps)
    //   addr42: OUT A
    //   addr43: HLT
    //
    // Expected result: 0xFF (255). If any conditional jump is broken, the
    // result falls into the trap and gives 99.
    reg [7:0] test_program [0:55];
    integer i;

    initial begin
        for (i = 0; i <= 55; i = i + 1)
            test_program[i] = 8'h00; // default filler: NOP

        test_program[0]  = 8'h08; // LD A
        test_program[1]  = 8'd50; //   #DATA_5
        test_program[2]  = 8'h09; // LD B
        test_program[3]  = 8'd51; //   #DATA_3
        test_program[4]  = 8'h19; // ADD B
        test_program[5]  = 8'h10; // ST A
        test_program[6]  = 8'd52; //   #SCRATCH
        test_program[7]  = 8'h0A; // LD C
        test_program[8]  = 8'd52; //   #SCRATCH
        test_program[9]  = 8'h22; // SUB C
        test_program[10] = 8'h51; // JZ
        test_program[11] = 8'd14; //   #14
        test_program[12] = 8'h50; // JMP (trap)
        test_program[13] = 8'd40; //   #40
        test_program[14] = 8'h08; // LD A
        test_program[15] = 8'd53; //   #DATA_F0
        test_program[16] = 8'h0B; // LD D
        test_program[17] = 8'd54; //   #DATA_0F
        test_program[18] = 8'h2B; // AND D
        test_program[19] = 8'h52; // JNZ (trap)
        test_program[20] = 8'd40; //   #40
        test_program[21] = 8'h33; // OR D
        test_program[22] = 8'h3B; // XOR D
        test_program[23] = 8'h58; // NOT
        test_program[24] = 8'h5A; // SHR
        test_program[25] = 8'h59; // SHL
        test_program[26] = 8'h4C; // IN E
        test_program[27] = 8'h1C; // ADD E
        test_program[28] = 8'h40; // OUT A
        test_program[29] = 8'hFF; // HLT

        test_program[40] = 8'h08; // LD A (trap: destination of broken jumps)
        test_program[41] = 8'd55; //   #DATA_99
        test_program[42] = 8'h40; // OUT A
        test_program[43] = 8'hFF; // HLT

        test_program[50] = 8'd5;   // DATA_5
        test_program[51] = 8'd3;   // DATA_3
        test_program[52] = 8'd0;   // SCRATCH (overwritten by ST)
        test_program[53] = 8'hF0;  // DATA_F0
        test_program[54] = 8'h0F;  // DATA_0F
        test_program[55] = 8'd99;  // DATA_99

        // Initial reset
        reset = 1;
        repeat (2) @(posedge clk);
        #1; // release the reset away from the edge, avoids a race with the FSM
        reset = 0;

        // Flash the program, byte by byte
        program_mode = 1;
        for (i = 0; i <= 55; i = i + 1) begin
            @(negedge clk);
            external_input = test_program[i];
            program_wr = 1;
            @(posedge clk);
            program_wr = 0;
        end
        program_mode = 0;

        // Reset so the PC goes back to 0 before executing
        reset = 1;
        repeat (2) @(posedge clk);
        #1;
        reset = 0;

        // Fixed value that IN will capture (addr26). Left stable for the
        // rest of the run, since IN is only used once in this program.
        external_input = 8'h01;

        // Let the program run (each instruction can take up to 4 states)
        repeat (100) @(posedge clk);

        if (external_output == 8'hFF)
            $display("PASS: external_output = %0d (expected 255)", external_output);
        else
            $display("FAIL: external_output = %0d (expected 255)", external_output);

        $finish;
    end

    initial begin
        $dumpfile("cpu_tb.vcd");
        $dumpvars(0, CPU_tb);
    end
endmodule
