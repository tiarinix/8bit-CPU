// 8-bit wide, 16-word deep memory

module MEM #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16
)(
    input logic clk,
    input logic reset,
    input logic [0:0]wr,
    input logic [WIDTH-1:0] Data_IN,
    input logic [$clog2(DEPTH)-1:0] addr,
    output logic [WIDTH-1:0] Data_OUT
);
    logic [WIDTH-1:0] mem [DEPTH-1:0];

    // Program memory is not cleared on reset: the CPU's reset only
    // reinitializes registers/PC, not the contents already flashed in.
    //
    // Latch-based instead of flip-flop-based: transparent while clk is
    // high, closes (holds) on the falling edge -- the same effective
    // capture instant as the negedge-triggered register this replaces, but
    // each bit costs one latch instead of a flip-flop's master+slave latch
    // pair, roughly halving the memory array's cell count. The gate is the
    // real `clk` (the design's one declared clock), not a derived/gated
    // signal, so STA's built-in latch time-borrowing analysis applies
    // normally instead of needing a custom SDC.
    always_latch begin
        if (clk && wr)
            mem[addr] = Data_IN;
    end

    assign Data_OUT = mem[addr];
endmodule
