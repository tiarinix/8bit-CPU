`timescale 1ns/1ps

// Individual test: HLT -- stops the CPU. Trap: if HLT doesn't halt
// execution, the program keeps going and loads a "bad" value (99) afterward.
module test_hlt;
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

        prog[0] = 8'h08; prog[1] = 8'd10; // LD A,#10   A=55
        prog[2] = 8'h40;                  // OUT A      output=55
        prog[3] = 8'hFF;                  // HLT
        prog[4] = 8'h08; prog[5] = 8'd11; // TRAP (should never execute): LD A,#11 (bad=99)
        prog[6] = 8'h40;                  // OUT A
        prog[7] = 8'hFF;                  // HLT
        prog[10] = 8'd55;
        prog[11] = 8'd99;

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

        if (external_output == 8'd55)
            $display("PASS HLT: external_output = %0d (expected 55)", external_output);
        else
            $display("FAIL HLT: external_output = %0d (expected 55)", external_output);

        $finish;
    end
endmodule
