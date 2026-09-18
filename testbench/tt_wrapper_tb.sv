`timescale 1ns/1ps

// Verifies the Tiny Tapeout wrapper: a minimal program driven through the
// fixed pinout (ui_in/uo_out/uio_in/rst_n) instead of CPU.sv's own ports.
// Confirms the reset polarity inversion and the program_mode/program_wr
// mapping to uio_in[1:0]. Full ISA verification lives in
// testbench/CPU_tb.sv (with MEM_DEPTH=64).

module tt_wrapper_tb;
    reg clk = 0;
    reg rst_n = 0;          // TT: active low (0 = in reset)
    reg [7:0] ui_in = 0;
    reg [7:0] uio_in = 0;   // uio_in[0]=program_mode, uio_in[1]=program_wr
    reg ena = 1;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_tiarinix_ttihp_verilog_template dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    always #5 clk = ~clk;

    // Minimal program (fits in the real 16 words of MEM_DEPTH, the same
    // size the production wrapper uses): LD A, LD B, ADD B, OUT A, HLT.
    // This testbench's goal is to validate the pin mapping and reset
    // polarity through the wrapper, not to re-verify the whole ISA (that's
    // already done by testbench/CPU_tb.sv with MEM_DEPTH=64).
    //   addr0: LD A,#14 (data 5)
    //   addr2: LD B,#15 (data 3)
    //   addr4: ADD B          -> A = 5+3 = 8
    //   addr5: OUT A          -> uo_out <- 8
    //   addr6: HLT
    //   addr14: data 5
    //   addr15: data 3
    reg [7:0] test_program [0:15];
    integer i;

    initial begin
        for (i = 0; i <= 15; i = i + 1)
            test_program[i] = 8'h00;

        test_program[0] = 8'h08; test_program[1] = 8'd14; // LD A,#14
        test_program[2] = 8'h09; test_program[3] = 8'd15; // LD B,#15
        test_program[4] = 8'h19;                          // ADD B
        test_program[5] = 8'h40;                          // OUT A
        test_program[6] = 8'hFF;                          // HLT

        test_program[14] = 8'd5; // data: 5
        test_program[15] = 8'd3; // data: 3

        // ---- Initial reset (rst_n=0 = in reset) ----
        rst_n = 0;
        repeat (2) @(posedge clk);
        #1;
        rst_n = 1;

        // ---- Flash the program via ui_in / uio_in[1:0] ----
        // Values are set mid-cycle (right after a posedge), not at the
        // exact instant of the edge that consumes them: going through the
        // wrapper (bit-select -> wrapper port -> CPU port) needs extra
        // propagation margin that the "everything on the negedge" pattern
        // doesn't leave when used through one more level of hierarchy.
        uio_in[0] = 1'b1; // program_mode
        for (i = 0; i <= 15; i = i + 1) begin
            @(posedge clk);
            ui_in = test_program[i];
            uio_in[1] = 1'b1; // program_wr
            @(negedge clk);
            uio_in[1] = 1'b0;
        end
        uio_in[0] = 1'b0;

        // ---- Reset so the PC goes back to 0 before executing ----
        rst_n = 0;
        repeat (2) @(posedge clk);
        #1;
        rst_n = 1;

        repeat (30) @(posedge clk);

        if (uo_out == 8'd8)
            $display("PASS: uo_out = %0d (expected 8)", uo_out);
        else
            $display("FAIL: uo_out = %0d (expected 8)", uo_out);

        $finish;
    end
endmodule
