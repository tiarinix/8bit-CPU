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
    // Latch-based instead of flip-flop-based: each word is its own
    // transparent latch (open while clk is high, closes on the falling
    // edge -- the same effective capture instant as the negedge-triggered
    // register this replaces), gated by a per-word chip-select decoded
    // from addr. One latch costs roughly half a flip-flop's area (a
    // flip-flop is internally a master+slave latch pair).
    //
    // This has to be spelled out as DEPTH separate always_latch blocks,
    // each targeting a single fixed array element (mem[i], i a genvar
    // constant) -- Yosys's latch inference doesn't support a single
    // always_latch block writing mem[addr] with addr a runtime signal
    // (tried that first; it failed with "No latch inferred for signal").
    genvar i;
    generate
        for (i = 0; i < DEPTH; i++) begin : word
            wire word_sel = (addr == i[$clog2(DEPTH)-1:0]);
            always_latch begin
                if (clk && wr && word_sel)
                    mem[i] = Data_IN;
            end
        end
    endgenerate

    assign Data_OUT = mem[addr];
endmodule
