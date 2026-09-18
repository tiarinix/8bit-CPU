module register #(
    parameter int WIDTH = 8
)(
    input logic clk,
    input logic reset,
    input logic [0:0]wr,
    input logic [WIDTH-1:0] Data_IN,
    output logic [WIDTH-1:0] Data_OUT = 0
);
    always_ff @(negedge clk) begin
        if (reset)
            Data_OUT <= {WIDTH{1'b0}};
        else if (wr)
            Data_OUT <= Data_IN;
    end
endmodule
