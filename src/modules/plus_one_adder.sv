// Adds one to the input value and returns it on the output

module PlusOneAdder #(
    parameter int WIDTH = 8
)(
    input logic [WIDTH-1:0] Data_IN,
    output logic [WIDTH-1:0] Data_OUT
);
    always_comb begin
        Data_OUT = Data_IN + 1;
    end
endmodule
