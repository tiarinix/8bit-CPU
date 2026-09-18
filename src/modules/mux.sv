module mux #(
    parameter int WIDTH = 8,
    parameter int N = 2,
    localparam int SEL_WIDTH = $clog2(N) //$clog2 computes the number of bits needed to represent N
)(
    input  logic [SEL_WIDTH-1:0] sel,
    input  logic [N*WIDTH-1:0]   Data_IN,
    output logic [WIDTH-1:0]     Data_OUT
);

    always_comb begin
        // Logical Data_IN[0] == first element in the concatenation {a, b, c, ...},
        // which in a packed vector ends up in the most-significant bits, which is
        // why it's indexed from the opposite end relative to sel.
        Data_OUT = Data_IN[(N-1-sel)*WIDTH +: WIDTH];
    end

endmodule
