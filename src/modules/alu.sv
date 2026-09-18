// 8-bit, 2-input ALU, with an 8-bit output and flags (overflow, zero, negative, carry) packed into one byte

module ALU #(
    parameter int WIDTH = 8
)(
    input  logic [WIDTH-1:0] A,
    input  logic [WIDTH-1:0] B,
    input  logic [2:0]       op,
    output logic [WIDTH-1:0] Y,
    output logic [WIDTH-1:0] flags   // bit0=carry, bit1=negative, bit2=zero, bit3=overflow, rest is 0
);
    logic overflow, zero, negative, carry;

    always_comb begin
        carry = 1'b0;   // default value: avoids a latch in cases that don't touch carry

        case (op)
            3'b000: {carry, Y} = A + B; // add
            3'b001: {carry, Y} = A - B; // subtract
            3'b010: Y = A & B; // AND
            3'b011: Y = A | B; // OR
            3'b100: Y = A ^ B; // XOR
            3'b101: Y = ~A; // NOT
            3'b110: Y = A << 1; // shift left
            3'b111: Y = A >> 1; // shift right
            default: Y = {WIDTH{1'b0}};
        endcase

        overflow = (op == 3'b000 && (A[WIDTH-1] == B[WIDTH-1]) && (Y[WIDTH-1] != A[WIDTH-1])) ||
                   (op == 3'b001 && (A[WIDTH-1] != B[WIDTH-1]) && (Y[WIDTH-1] != A[WIDTH-1]));
        zero     = (Y == {WIDTH{1'b0}});
        negative = Y[WIDTH-1];

        flags = {{(WIDTH-4){1'b0}}, overflow, zero, negative, carry};
    end
endmodule
