`timescale 1ns/1ps

// Individual test: JN addr -- jumps if negative=1. Forced with ADD A on 127
// (127+127=254=0xFE, bit7=1 -> negative=1).
module test_jn;
    reg clk = 0;
    reg reset = 0;
    reg program_mode = 0;
    reg program_wr = 0;
    reg [7:0] external_input = 0;
    wire [7:0] external_output;

    CPU #(.MEM_DEPTH(32)) dut (
        .clk(clk), .reset(reset), .program_mode(program_mode), .program_wr(program_wr),
        .external_input(external_input), .external_output(external_output)
    );

    always #5 clk = ~clk;

    reg [7:0] prog [0:31];
    integer i;

    initial begin
        for (i = 0; i <= 31; i = i + 1) prog[i] = 8'h00;

        prog[0] = 8'h08; prog[1] = 8'd20; // LD A,#20   A=127
        prog[2] = 8'h18;                  // ADD A      A=254, negative=1
        prog[3] = 8'h55; prog[4] = 8'd9;  // JN #9      should jump
        prog[5] = 8'h08; prog[6] = 8'd21; // TRAP: LD A,#21 (bad=99)
        prog[7] = 8'h40;                  // OUT A
        prog[8] = 8'hFF;                  // HLT
        prog[9] = 8'h08; prog[10] = 8'd22; // CORRECT: LD A,#22 (good=42)
        prog[11] = 8'h40;                 // OUT A
        prog[12] = 8'hFF;                 // HLT
        prog[20] = 8'd127;
        prog[21] = 8'd99;
        prog[22] = 8'd42;

        reset = 1; repeat (2) @(posedge clk); #1; reset = 0;

        program_mode = 1;
        for (i = 0; i <= 31; i = i + 1) begin
            @(negedge clk);
            external_input = prog[i];
            program_wr = 1;
            @(posedge clk);
            program_wr = 0;
        end
        program_mode = 0;

        reset = 1; repeat (2) @(posedge clk); #1; reset = 0;

        repeat (40) @(posedge clk);

        if (external_output == 8'd42)
            $display("PASS JN: external_output = %0d (expected 42)", external_output);
        else
            $display("FAIL JN: external_output = %0d (expected 42)", external_output);

        $finish;
    end
endmodule
