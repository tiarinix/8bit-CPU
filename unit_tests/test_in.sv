`timescale 1ns/1ps

// Individual test: IN reg -- reg <- external_input
module test_in;
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

        prog[0] = 8'h48; // IN A
        prog[1] = 8'h40; // OUT A
        prog[2] = 8'hFF; // HLT

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

        external_input = 8'd77; // value that IN will capture

        repeat (40) @(posedge clk);

        if (external_output == 8'd77)
            $display("PASS IN: external_output = %0d (expected 77)", external_output);
        else
            $display("FAIL IN: external_output = %0d (expected 77)", external_output);

        $finish;
    end
endmodule
