// Tiny Tapeout wrapper: adapts the platform's fixed pinout (ui_in/uo_out/
// uio_*/ena/clk/rst_n) to CPU.sv's own port. Does not modify the datapath,
// it only maps signals.
//
// Depends on CPU.sv (and, transitively, everything under modules/). No
// `include here on purpose: see the note at the top of CPU.sv.

module tt_um_tiarinix_ttihp_verilog_template (
    input  wire [7:0] ui_in,    // dedicated inputs -> external_input
    output wire [7:0] uo_out,   // dedicated outputs <- external_output
    input  wire [7:0] uio_in,   // bidirectional (input): [0]=program_mode, [1]=program_wr
    output wire [7:0] uio_out,  // bidirectional (output): unused
    output wire [7:0] uio_oe,   // bidirectional (direction): all set as input
    input  wire       ena,      // high when the design is selected (unused)
    input  wire        clk,
    input  wire        rst_n    // TT reset: active LOW
);

    // CPU.sv uses an active-HIGH reset; TT provides an active-LOW rst_n.
    wire reset = ~rst_n;

    // Silences "unused" linter warnings: ena and the uio_in bits we don't
    // use (only bits 0 and 1 are used).
    wire _unused = &{ena, uio_in[7:2], 1'b0};

    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00; // all 8 bidirectional pins are set as input

    CPU #(.MEM_DEPTH(8)) cpu_inst (
        .clk(clk),
        .reset(reset),
        .program_mode(uio_in[0]),
        .program_wr(uio_in[1]),
        .external_input(ui_in),
        .external_output(uo_out)
    );

endmodule
