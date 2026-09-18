// CPU layout
//
// Depends on: modules/alu.sv, modules/control.sv, modules/memory.sv,
// modules/mux.sv, modules/plus_one_adder.sv, modules/register.sv,
// modules/tristate_buffer.sv. No `include here on purpose: every source
// file is compiled together as an explicit list (see info.yaml
// source_files and run_sim.sh), matching how Tiny Tapeout's synthesis
// flow reads multi-file designs.

module CPU #(
    parameter int MEM_DEPTH = 16   // adjust based on leftover area when doing the layout
) (
    input  wire       clk,
    input  wire       reset,
    input  wire       program_mode,
    input  wire       program_wr,
    input  wire [7:0] external_input,
    output wire [7:0] external_output
);

    localparam int ADDR_WIDTH = $clog2(MEM_DEPTH);

    // ---- Main bus ----
    wire [7:0] bus;

    // ---- Halt / internal clocks ----
    wire halt_set;
    reg  halted;

    // PC and memory: freeze on HALT, but stay alive during flashing
    wire mem_pc_clk = clk & ~halted;
    // Rest of the CPU: freezes on HALT and also during flashing
    wire cpu_clk    = clk & ~halted & ~program_mode;

    always @(posedge clk or posedge reset) begin
        if (reset)
            halted <= 1'b0;
        else if (halt_set)
            halted <= 1'b1;
    end

    // ============ External input ============

    wire ext_in_wr, ext_in_en;
    wire [7:0] ext_in_out;

    register #(.WIDTH(8)) reg_ext_in (
        .clk(cpu_clk), .reset(reset),
        .wr(ext_in_wr), .Data_IN(external_input), .Data_OUT(ext_in_out)
    );

    TRIStateBuffer #(.WIDTH(8)) tristate_ext_in (
        .Data_IN(ext_in_out), .enable(ext_in_en & ~program_mode), .Data_OUT(bus)
    );

    // ============ External output ============

    wire ext_out_wr;

    register #(.WIDTH(8)) reg_ext_out (
        .clk(cpu_clk), .reset(reset),
        .wr(ext_out_wr), .Data_IN(bus), .Data_OUT(external_output)
    );

    // ============ General-purpose registers: A, B, C, D, E ============
    // A single select+wr pair from CONTROL (reg_dest_sel/reg_dest_wr) instead
    // of one wr per register; decoded here into one enable per register.

    wire [2:0] reg_dest_sel;
    wire       reg_dest_wr;

    wire reg_a_wr = reg_dest_wr & (reg_dest_sel == 3'd0);
    wire reg_b_wr = reg_dest_wr & (reg_dest_sel == 3'd1);
    wire reg_c_wr = reg_dest_wr & (reg_dest_sel == 3'd2);
    wire reg_d_wr = reg_dest_wr & (reg_dest_sel == 3'd3);
    wire reg_e_wr = reg_dest_wr & (reg_dest_sel == 3'd4);

    wire [7:0] reg_a_out, reg_b_out, reg_c_out, reg_d_out, reg_e_out;

    register #(.WIDTH(8)) reg_a (
        .clk(cpu_clk), .reset(reset),
        .wr(reg_a_wr), .Data_IN(bus), .Data_OUT(reg_a_out)
    );

    register #(.WIDTH(8)) reg_b (
        .clk(cpu_clk), .reset(reset),
        .wr(reg_b_wr), .Data_IN(bus), .Data_OUT(reg_b_out)
    );

    register #(.WIDTH(8)) reg_c (
        .clk(cpu_clk), .reset(reset),
        .wr(reg_c_wr), .Data_IN(bus), .Data_OUT(reg_c_out)
    );

    register #(.WIDTH(8)) reg_d (
        .clk(cpu_clk), .reset(reset),
        .wr(reg_d_wr), .Data_IN(bus), .Data_OUT(reg_d_out)
    );

    register #(.WIDTH(8)) reg_e (
        .clk(cpu_clk), .reset(reset),
        .wr(reg_e_wr), .Data_IN(bus), .Data_OUT(reg_e_out)
    );

    // ============ ALU ============

    wire [2:0] alu_sel_a, alu_sel_b;
    wire [2:0] alu_op;
    wire [7:0] alu_in_a, alu_in_b, alu_result, alu_flags;

    mux #(.WIDTH(8), .N(5)) mux_alu_a (
        .sel(alu_sel_a),
        .Data_IN({reg_a_out, reg_b_out, reg_c_out, reg_d_out, reg_e_out}),
        .Data_OUT(alu_in_a)
    );

    mux #(.WIDTH(8), .N(5)) mux_alu_b (
        .sel(alu_sel_b),
        .Data_IN({reg_a_out, reg_b_out, reg_c_out, reg_d_out, reg_e_out}),
        .Data_OUT(alu_in_b)
    );

    ALU #(.WIDTH(8)) alu (
        .A(alu_in_a), .B(alu_in_b), .op(alu_op),
        .Y(alu_result), .flags(alu_flags)
    );

    // ============ Flags register ============

    wire reg_f_wr;
    wire [7:0] reg_f_out;

    register #(.WIDTH(8)) reg_f (
        .clk(cpu_clk), .reset(reset),
        .wr(reg_f_wr), .Data_IN(alu_flags), .Data_OUT(reg_f_out)
    );

    // ============ ALU output register ============

    wire alu_out_wr, alu_out_en;
    wire [7:0] alu_out_data;

    register #(.WIDTH(8)) reg_alu_out (
        .clk(cpu_clk), .reset(reset),
        .wr(alu_out_wr), .Data_IN(alu_result), .Data_OUT(alu_out_data)
    );

    TRIStateBuffer #(.WIDTH(8)) tristate_alu_out (
        .Data_IN(alu_out_data), .enable(alu_out_en & ~program_mode), .Data_OUT(bus)
    );

    // ============ Output to bus: registers A..E ============

    wire [2:0] bus_out_sel;
    wire [7:0] bus_out_data;
    wire bus_out_en;

    mux #(.WIDTH(8), .N(5)) mux_bus_out (
        .sel(bus_out_sel),
        .Data_IN({reg_a_out, reg_b_out, reg_c_out, reg_d_out, reg_e_out}),
        .Data_OUT(bus_out_data)
    );

    TRIStateBuffer #(.WIDTH(8)) tristate_bus_out (
        .Data_IN(bus_out_data), .enable(bus_out_en & ~program_mode), .Data_OUT(bus)
    );

    // ============ Program Counter (PC) ============

    wire pc_wr, pc_sel;
    wire [7:0] pc_out, pc_plus_one, pc_next;

    // In flashing mode, the PC advances with program_wr instead of normal control
    wire [7:0] pc_data_in  = program_mode ? pc_plus_one : pc_next;
    wire       pc_wr_final = program_mode ? program_wr  : pc_wr;

    register #(.WIDTH(8)) reg_pc (
        .clk(mem_pc_clk), .reset(reset),
        .wr(pc_wr_final), .Data_IN(pc_data_in), .Data_OUT(pc_out)
    );

    PlusOneAdder #(.WIDTH(8)) pc_incrementer (
        .Data_IN(pc_out), .Data_OUT(pc_plus_one)
    );

    mux #(.WIDTH(8), .N(2)) mux_pc_next (
        .sel(pc_sel),
        .Data_IN({bus, pc_plus_one}),
        .Data_OUT(pc_next)
    );

    // ============ Memory address register ============
    // No longer needs a mux: it's always loaded from the bus (the fetch of
    // the second byte of LDA/LDB puts it there). Addressing towards PC for
    // instruction fetch is handled separately, in mem_addr_normal below.

    wire addr_wr;
    wire [7:0] addr_out;

    register #(.WIDTH(8)) reg_addr (
        .clk(cpu_clk), .reset(reset),
        .wr(addr_wr), .Data_IN(bus), .Data_OUT(addr_out)
    );

    // ============ Memory ============

    wire mem_wr, mem_out_en, mem_addr_sel;
    wire [7:0] mem_out;

    // mem_addr_sel: 0 = use ADDR (data read/write), 1 = use PC (fetch)
    wire [7:0] mem_addr_normal = mem_addr_sel ? pc_out : addr_out;

    // In flashing mode: writes external_input into mem[PC] and uses PC as the address
    wire [7:0]             mem_data_in_final = program_mode ? external_input : bus;
    wire [ADDR_WIDTH-1:0]  mem_addr_final    = program_mode ? pc_out[ADDR_WIDTH-1:0] : mem_addr_normal[ADDR_WIDTH-1:0];
    wire                   mem_wr_final      = program_mode ? program_wr : mem_wr;

    MEM #(.WIDTH(8), .DEPTH(MEM_DEPTH)) mem (
        .clk(mem_pc_clk), .reset(reset),
        .wr(mem_wr_final), .Data_IN(mem_data_in_final), .addr(mem_addr_final), .Data_OUT(mem_out)
    );

    TRIStateBuffer #(.WIDTH(8)) tristate_mem_out (
        .Data_IN(mem_out), .enable(mem_out_en & ~program_mode), .Data_OUT(bus)
    );

    // ============ Controller ============

    wire ir_wr;
    wire [7:0] ir_out;

    register #(.WIDTH(8)) reg_ir (
        .clk(cpu_clk), .reset(reset),
        .wr(ir_wr), .Data_IN(bus), .Data_OUT(ir_out)
    );

    control control_unit (
        .clk(cpu_clk),
        .reset(reset),
        .ir_out(ir_out),
        .reg_f_out(reg_f_out),

        .ext_in_wr(ext_in_wr),
        .ext_in_en(ext_in_en),
        .ext_out_wr(ext_out_wr),

        .reg_dest_sel(reg_dest_sel),
        .reg_dest_wr(reg_dest_wr),

        .reg_f_wr(reg_f_wr),

        .alu_sel_a(alu_sel_a),
        .alu_sel_b(alu_sel_b),
        .alu_op(alu_op),
        .alu_out_wr(alu_out_wr),
        .alu_out_en(alu_out_en),

        .bus_out_sel(bus_out_sel),
        .bus_out_en(bus_out_en),

        .pc_wr(pc_wr),
        .pc_sel(pc_sel),

        .addr_wr(addr_wr),

        .mem_addr_sel(mem_addr_sel),
        .mem_wr(mem_wr),
        .mem_out_en(mem_out_en),

        .ir_wr(ir_wr),

        .halt(halt_set)
    );

endmodule
