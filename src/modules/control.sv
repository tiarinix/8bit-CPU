module control (
    input  wire       clk,
    input  wire       reset,
    input  wire       en,      // freezes the state register (HALT / flashing)
    input  wire [7:0] ir_out,
    input  wire [7:0] reg_f_out,   // bit0=carry, bit1=negative, bit2=zero, bit3=overflow

    // External input / output
    output reg        ext_in_wr,
    output reg        ext_in_en,
    output reg        ext_out_wr,

    // Destination general-purpose register (A..E): a single select+wr pair
    // instead of one wr per register, to scale to 5 registers without
    // exploding the port count.
    output reg [2:0]  reg_dest_sel,
    output reg        reg_dest_wr,

    // Flags register
    output reg        reg_f_wr,

    // ALU
    output reg [2:0]  alu_sel_a,
    output reg [2:0]  alu_sel_b,
    output reg [2:0]  alu_op,
    output reg        alu_out_wr,
    output reg        alu_out_en,

    // Output to bus from A..E
    output reg [2:0]  bus_out_sel,
    output reg        bus_out_en,

    // Program Counter
    output reg        pc_wr,
    output reg        pc_sel,

    // Memory address register (always loaded from the bus)
    output reg        addr_wr,

    // Memory: where the address comes from (0 = ADDR register, 1 = PC)
    output reg        mem_addr_sel,
    output reg        mem_wr,
    output reg        mem_out_en,

    // Instruction Register
    output reg        ir_wr,

    // Halt
    output reg        halt
);

    // ---- General-purpose registers ----
    localparam [2:0] REG_A = 3'd0;
    localparam [2:0] REG_B = 3'd1;
    localparam [2:0] REG_C = 3'd2;
    localparam [2:0] REG_D = 3'd3;
    localparam [2:0] REG_E = 3'd4;
    // 3'd5..3'd7 invalid: fall into the default of each case (no-op)

    // ---- Opcodes: family in ir_out[7:3], register/condition in ir_out[2:0] ----
    localparam [7:0] OP_NOP = 8'h00;
    localparam [7:0] OP_HLT = 8'hFF;

    localparam [4:0] FAM_LD     = 5'd1;  // 0x08-0x0C: reg <- mem[addr]
    localparam [4:0] FAM_ST     = 5'd2;  // 0x10-0x14: mem[addr] <- reg
    localparam [4:0] FAM_ADD    = 5'd3;  // 0x18-0x1C: A <- A + reg
    localparam [4:0] FAM_SUB    = 5'd4;  // 0x20-0x24: A <- A - reg
    localparam [4:0] FAM_AND    = 5'd5;  // 0x28-0x2C: A <- A & reg
    localparam [4:0] FAM_OR     = 5'd6;  // 0x30-0x34: A <- A | reg
    localparam [4:0] FAM_XOR    = 5'd7;  // 0x38-0x3C: A <- A ^ reg
    localparam [4:0] FAM_OUT    = 5'd8;  // 0x40-0x44: external_output <- reg
    localparam [4:0] FAM_IN     = 5'd9;  // 0x48-0x4C: reg <- external_input
    localparam [4:0] FAM_JCC    = 5'd10; // 0x50-0x56: jump (conditional, per field)
    localparam [4:0] FAM_SINGLE = 5'd11; // 0x58-0x5A: NOT/SHL/SHR (operate on A)
    localparam [4:0] FAM_CMP    = 5'd12; // 0x60-0x64: flags <- A - reg (A untouched)

    localparam [2:0] SINGLE_NOT = 3'b000;
    localparam [2:0] SINGLE_SHL = 3'b001;
    localparam [2:0] SINGLE_SHR = 3'b010;

    localparam [2:0] COND_ALWAYS = 3'b000; // JMP
    localparam [2:0] COND_Z      = 3'b001; // JZ
    localparam [2:0] COND_NZ     = 3'b010; // JNZ
    localparam [2:0] COND_C      = 3'b011; // JC
    localparam [2:0] COND_NC     = 3'b100; // JNC
    localparam [2:0] COND_N      = 3'b101; // JN
    localparam [2:0] COND_O      = 3'b110; // JO
    // 3'b111 reserved: never jumps

    localparam [2:0] ALU_ADD = 3'b000;
    localparam [2:0] ALU_SUB = 3'b001;
    localparam [2:0] ALU_AND = 3'b010;
    localparam [2:0] ALU_OR  = 3'b011;
    localparam [2:0] ALU_XOR = 3'b100;
    localparam [2:0] ALU_NOT = 3'b101;
    localparam [2:0] ALU_SHL = 3'b110;
    localparam [2:0] ALU_SHR = 3'b111;

    wire [4:0] family = ir_out[7:3];
    wire [2:0] field  = ir_out[2:0]; // register or condition, depending on the family

    wire flag_carry    = reg_f_out[0];
    wire flag_negative = reg_f_out[1];
    wire flag_zero     = reg_f_out[2];
    wire flag_overflow = reg_f_out[3];

    reg jump_taken;
    always @(*) begin
        case (field)
            COND_ALWAYS: jump_taken = 1'b1;
            COND_Z:      jump_taken = flag_zero;
            COND_NZ:     jump_taken = ~flag_zero;
            COND_C:      jump_taken = flag_carry;
            COND_NC:     jump_taken = ~flag_carry;
            COND_N:      jump_taken = flag_negative;
            COND_O:      jump_taken = flag_overflow;
            default:     jump_taken = 1'b0; // invalid condition code: never jumps
        endcase
    end

    // ---- Instruction cycle states ----
    localparam STATE_FETCH1  = 2'b00; // IR <- mem[PC], PC++
    localparam STATE_FETCH2  = 2'b01; // only for instructions with an operand: ADDR <- mem[PC], PC++
    localparam STATE_EXECUTE = 2'b10;
    localparam STATE_STORE   = 2'b11;

    reg [1:0] state;

    // Instructions that need a second byte (address) before executing.
    // ir_out is already loaded with the opcode on the negedge inside
    // STATE_FETCH1, so this decision doesn't need to wait an extra cycle.
    wire needs_operand = (family == FAM_LD) || (family == FAM_ST) || (family == FAM_JCC);

    always @(posedge clk or posedge reset) begin
        if (reset)
            state <= STATE_FETCH1;
        else if (en) begin
            case (state)
                STATE_FETCH1:  state <= needs_operand ? STATE_FETCH2 : STATE_EXECUTE;
                STATE_FETCH2:  state <= STATE_EXECUTE;
                STATE_EXECUTE: state <= STATE_STORE;
                STATE_STORE:   state <= STATE_FETCH1;
                default:       state <= STATE_FETCH1;
            endcase
        end
    end

    always @(*) begin
        // Default values: everything off
        ext_in_wr    = 0;
        ext_in_en    = 0;
        ext_out_wr   = 0;

        reg_dest_sel = 3'b000;
        reg_dest_wr  = 0;

        reg_f_wr     = 0;

        alu_sel_a    = 3'b000;
        alu_sel_b    = 3'b000;
        alu_op       = 3'b000;
        alu_out_wr   = 0;
        alu_out_en   = 0;

        bus_out_sel  = 3'b000;
        bus_out_en   = 0;

        pc_wr        = 0;
        pc_sel       = 0;

        addr_wr      = 0;

        mem_addr_sel = 1'b1; // default: fetch address (PC)
        mem_wr       = 0;
        mem_out_en   = 0;

        ir_wr        = 0;

        halt         = 0;

        case (state)

            // ---- 1. Fetch opcode: IR <- mem[PC], PC <- PC+1 ----
            STATE_FETCH1: begin
                mem_addr_sel = 1'b1; // PC
                mem_out_en   = 1;
                ir_wr        = 1;
                pc_sel       = 1;    // selects pc_plus_one
                pc_wr        = 1;
            end

            // ---- 1b. Fetch the operand: reads mem[PC] and routes it to ADDR
            //          (or straight to PC if it's a jump that's taken) ----
            STATE_FETCH2: begin
                mem_addr_sel = 1'b1; // PC
                mem_out_en   = 1;
                if (family == FAM_JCC) begin
                    if (jump_taken) begin
                        pc_sel = 1'b0; // bus (target address) -> PC, without incrementing
                        pc_wr  = 1'b1;
                    end else begin
                        pc_sel = 1'b1; // condition not met: continue sequentially
                        pc_wr  = 1'b1;
                    end
                end else begin
                    addr_wr = 1'b1; // ADDR <- bus (address byte just read)
                    pc_sel  = 1'b1;
                    pc_wr   = 1'b1;
                end
            end

            // ---- 2. Decode / Execute ----
            STATE_EXECUTE: begin
                case (family)
                    FAM_LD, FAM_ST, FAM_JCC: begin
                        // already resolved in FETCH2 (LD/ST finish in STORE), nothing to do
                    end
                    FAM_ADD: begin
                        alu_sel_a  = REG_A;
                        alu_sel_b  = field;
                        alu_op     = ALU_ADD;
                        alu_out_wr = 1;
                        reg_f_wr   = 1;
                    end
                    FAM_SUB: begin
                        alu_sel_a  = REG_A;
                        alu_sel_b  = field;
                        alu_op     = ALU_SUB;
                        alu_out_wr = 1;
                        reg_f_wr   = 1;
                    end
                    FAM_AND: begin
                        alu_sel_a  = REG_A;
                        alu_sel_b  = field;
                        alu_op     = ALU_AND;
                        alu_out_wr = 1;
                        reg_f_wr   = 1;
                    end
                    FAM_OR: begin
                        alu_sel_a  = REG_A;
                        alu_sel_b  = field;
                        alu_op     = ALU_OR;
                        alu_out_wr = 1;
                        reg_f_wr   = 1;
                    end
                    FAM_XOR: begin
                        alu_sel_a  = REG_A;
                        alu_sel_b  = field;
                        alu_op     = ALU_XOR;
                        alu_out_wr = 1;
                        reg_f_wr   = 1;
                    end
                    FAM_CMP: begin
                        // same as SUB, but the result is discarded: only the flags remain
                        alu_sel_a = REG_A;
                        alu_sel_b = field;
                        alu_op    = ALU_SUB;
                        reg_f_wr  = 1;
                    end
                    FAM_OUT: begin
                        bus_out_sel = field;
                        bus_out_en  = 1;
                        ext_out_wr  = 1;
                    end
                    FAM_IN: begin
                        ext_in_wr = 1; // captures external_input -> reg_ext_in
                    end
                    FAM_SINGLE: begin
                        alu_sel_a = REG_A;
                        case (field)
                            SINGLE_NOT: alu_op = ALU_NOT;
                            SINGLE_SHL: alu_op = ALU_SHL;
                            SINGLE_SHR: alu_op = ALU_SHR;
                            default:    alu_op = ALU_NOT; // invalid field: should not happen
                        endcase
                        alu_out_wr = 1;
                        reg_f_wr   = 1;
                    end
                    default: begin
                        // OP_NOP, OP_HLT (don't fall into any family) and unknown opcodes
                        if (ir_out == OP_HLT)
                            halt = 1;
                    end
                endcase
            end

            // ---- 3. Store ----
            STATE_STORE: begin
                case (family)
                    FAM_LD: begin
                        mem_addr_sel = 1'b0; // ADDR: data address
                        mem_out_en   = 1;
                        reg_dest_sel = field;
                        reg_dest_wr  = 1;
                    end
                    FAM_ST: begin
                        bus_out_sel  = field;
                        bus_out_en   = 1;
                        mem_addr_sel = 1'b0; // ADDR: destination address
                        mem_wr       = 1;
                    end
                    FAM_ADD, FAM_SUB, FAM_AND, FAM_OR, FAM_XOR, FAM_SINGLE: begin
                        // ALU result (already computed in EXECUTE) -> A
                        alu_out_en   = 1;
                        reg_dest_sel = REG_A;
                        reg_dest_wr  = 1;
                    end
                    FAM_IN: begin
                        ext_in_en    = 1; // reg_ext_in -> bus
                        reg_dest_sel = field;
                        reg_dest_wr  = 1;
                    end
                    default: begin
                        // NOP, CMP, OUT, JMP/Jcc, HLT: nothing else
                    end
                endcase
            end

            default: begin end
        endcase
    end

endmodule
