module TRIStateBuffer #(
    parameter int WIDTH = 8
)(
    input logic [WIDTH-1:0] Data_IN,
    input logic enable,
    output wire [WIDTH-1:0] Data_OUT
);

    assign Data_OUT = enable ? Data_IN : 'z;
endmodule
