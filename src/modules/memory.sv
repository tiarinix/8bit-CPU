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
    always_ff @(negedge clk) begin
        if (wr)
            mem[addr] <= Data_IN;
    end

    assign Data_OUT = mem[addr];
endmodule
