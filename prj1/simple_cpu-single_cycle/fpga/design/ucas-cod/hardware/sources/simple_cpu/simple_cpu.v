`timescale 10ns / 1ns
`define EXTEND_WIDTH 32
`define ADDR_WIDTH 5

module simple_cpu(
	input             clk,
	input             rst,

	output [31:0]     PC,
	input  [31:0]     Instruction,

	output [31:0]     Address,
	output            MemWrite,
	output [31:0]     Write_data,
	output [ 3:0]     Write_strb,

	input  [31:0]     Read_data,
	output            MemRead
);

	// THESE THREE SIGNALS ARE USED IN OUR TESTBENCH
	// PLEASE DO NOT MODIFY SIGNAL NAMES
	// AND PLEASE USE THEM TO CONNECT PORTS
	// OF YOUR INSTANTIATION OF THE REGISTER FILE MODULE
	wire			RF_wen;
	wire [4:0]		RF_waddr;
	wire [31:0]		RF_wdata;

	// TODO: PLEASE ADD YOUR CODE BELOW

//ID
	wire [5:0] opcode;
	wire [4:0] rs;
	wire [4:0] rt;
	wire [4:0] rd;
	wire [4:0] shamt;
	wire [5:0] func;
	assign {opcode,rs,rt,rd,shamt,func} = Instruction;

	wire R_Type;
	wire R_Type_calc;
	wire R_Type_jump;
	wire R_Type_mov;
	wire R_Type_shift;

	wire REGIMM;
	wire J_Type;

	wire I_Type_b;
	wire I_Type_calc;
	wire I_Type_mr;
	wire I_Type_mw;

	assign R_Type		= opcode[5:0] == 6'b000000;
	assign R_Type_calc	= R_Type & func[5];
	assign R_Type_shift	= R_Type & (func[5:3]==3'b000);
	assign R_Type_jump	= R_Type & ({func[5:3],func[1]}==4'b0010);
	assign R_Type_mov	= R_Type & ({func[5:3],func[1]}==4'b0011);
	assign REGIMM 		= opcode[5:0] == 6'b000001;
	assign J_Type 		= opcode[5:1] == 5'b00001;
	assign I_Type_b 	= opcode[5:2] == 4'b0001;
	assign I_Type_calc 	= opcode[5:3] == 3'b001;
	assign I_Type_mr	= opcode[5:3] == 3'b100;
	assign I_Type_mw	= opcode[5:3] == 3'b101;

	wire RegDst,Branch,MemtoReg,ALUEn,ShiftEn,ALU_IM,Shift_IM;

	assign RegDst 	= R_Type;
	assign Branch 	= REGIMM | I_Type_b;
	assign ALUEn	= R_Type_calc | REGIMM | I_Type_b | I_Type_calc | I_Type_mr | I_Type_mw;
	assign ShiftEn	= R_Type_shift; 
	assign ALU_IM	= I_Type_calc | I_Type_mr | I_Type_mw; //立即数计算
	assign Shift_IM = ~func[2]; //立即数移位
	assign MemWrite = I_Type_mw;
	assign MemRead 	= I_Type_mr;
	assign MemtoReg = I_Type_mr;
	assign RF_wen	= (R_Type & 
			~(R_Type_mov & (func[0] ^ (|RF_rdata2))) & //move指令条件满足才写
			~(R_Type_jump & ~func[0])) | //jr指令RF_wen不能位1
			J_Type & opcode[0] | I_Type_calc | I_Type_mr; 

	//EXTEND_IMM
	wire [31:0] SignExtend;
	// sign extend
	assign SignExtend = {{(16){Instruction[15]}}, Instruction[15:0]};
	//Zero extend for andi, ori, xori
	wire [31:0] ZeroExtend;
	assign ZeroExtend = {16'b0, Instruction[15:0]};
	//Select
	wire [31:0] ExtendedImm;
	assign ExtendedImm = (opcode[5:2] == 4'b0011) ? ZeroExtend : SignExtend;

	//PC
	reg  [31:0] PC;
	wire [31:0] new_PC;
	wire [31:0] PC_normal;
	wire [31:0] PC_abnormal;
	assign PC_normal = PC + 4;
	assign new_PC = (Branch & (Zero ^ (
			REGIMM & ~Instruction[16] 
			| I_Type_b & (opcode[0] ^ (opcode[1] & (|RF_rdata1)))))) ? PC_abnormal : PC_normal;//是否branch

	always @(posedge clk) begin
		if(rst) begin
			PC <= 32'd0;
		end 
		else if(R_Type_jump) begin
			PC <= RF_rdata1;
		end
		else if(J_Type) begin
			PC <= {PC_normal[31:28], Instruction[25:0], 2'b00};
		end
		else begin
			PC <= new_PC;
		end
	end
	
	//Registers
	wire [31:0] RF_rdata1;
	wire [31:0] RF_rdata2;
	 
	assign RF_waddr = {(5){R_Type}} & rd | 
			{(5){I_Type_mr | I_Type_calc}} & rt | 
			{(5){J_Type}} & 5'b11111;
	

	reg_file Registers(
		.clk	(clk),
		.waddr	(RF_waddr),
		.raddr1	(rs),
		.raddr2	(rt),
		.wen	(RF_wen),
		.wdata	(RF_wdata),
		.rdata1	(RF_rdata1),
		.rdata2	(RF_rdata2)
	);

	//ALUop && Shiftop
	wire [2:0] ALUop;
	wire [1:0] Shiftop;

	assign ALUop = {(3){R_Type_calc}} & {func[1] & ~(func[3] & func[0]), ~func[2], func[3] & ~func[2] & func[1] | func[2] & func[0]} | 
			{(3){I_Type_calc}} & {opcode[1] & ~(opcode[3] & opcode[0]), ~opcode[2],opcode[3] & ~opcode[2] & opcode[1] | opcode[2] & opcode[0]} | 
			{(3){REGIMM}} | 
			{(3){I_Type_b}}	 & {2'b11, opcode[1]} | // slt 111 sub 110
	  		{(3){I_Type_mr | I_Type_mw}} & 3'b010;

	assign Shiftop = func[1:0];

//EX
	wire Overflow;
	wire CarryOut,Zero;
	wire [31:0] Result;
	wire [31:0] ALUResult;
	wire [31:0] ShifterResult;

	//ALU
	alu ALU(
		.A		(RF_rdata1),
		.B		(ALU_IM ? ExtendedImm : REGIMM ? 32'b0 :RF_rdata2),
		.ALUop		(ALUop),
		.Overflow	(Overflow),
		.CarryOut	(CarryOut),
		.Zero		(Zero),
		.Result		(ALUResult)
	);

	shifter Shifter(
		.A		(RF_rdata2),
		.B		(Shift_IM ? shamt : RF_rdata1[4:0]),//移位对32取模
		.Shiftop	(Shiftop),
		.Result		(ShifterResult)
	);

	//Result
	assign Result = {(32){ALUEn}} & ALUResult | 
			{(32){ShiftEn}} & ShifterResult;
	
	//PC_abnormal
	wire [31:0] PC_offset;
	assign PC_offset 	= {SignExtend[29:0], 2'b00}; //offset*4
	assign PC_abnormal 	= PC_normal + PC_offset;

//MEM
	
	//Data Memory
	assign Address		= Result & ~32'b11; //对齐
	assign Write_data	= (opcode[2:0] == 3'b010) ? RF_rdata2 >> {~Result[1:0], 3'b0} : RF_rdata2 << {Result[1:0], 3'b0}; //除swl外移位规则相同

	assign Write_strb 	= {(4){~opcode[2] & opcode[1] & ~opcode[0]}} & {Result[1] & Result[0], Result[1], Result[1] | Result[0], 1'b1} | //swl
				{(4){ opcode[2] & opcode[1] & ~opcode[0]}} & {1'b1, ~(Result[1] & Result[0]), ~Result[1], ~(Result[1] | Result[0])} | //swr
			  	{(4){~opcode[1] | opcode[0]}} &{( Result[1] | opcode[1]) & ( Result[0] | opcode[0]),
						   	 	( Result[1] | opcode[1]) & (~Result[0] | opcode[0]),
						   	 	(~Result[1] | opcode[1]) & ( Result[0] | opcode[0]),
						     		(~Result[1] | opcode[1]) & (~Result[0] | opcode[0])};
	
	//WB
	wire [31:0] Read_data_shifted;
	wire [31:0] Read_data_masked;
	wire Read_data_sign; 
	wire [31:0] Read_data_unaligned;
	assign Read_data_shifted 	= Read_data >> {Result[1:0], 3'b0};
	assign Read_data_sign 		= Read_data_shifted[(opcode[1:0]==2'b01) ? 15 : 7];//符号位

	assign Read_data_masked 	= Read_data_shifted & {{(16){opcode[1]}}, {(8){opcode[0]}}, {(8){1'b1}}} | 
					{(32){~opcode[2] & Read_data_sign}} & ~{{(16){opcode[1]}}, {(8){opcode[0]}}, {(8){1'b1}}};//字节掩码进行有符号扩展

	assign Read_data_unaligned 	= {(32){~opcode[2]}} & ((Read_data << {~Result[1:0], 3'b0}) | RF_rdata2 & ({(32){1'b1}} >> { Result[1:0], 3'b0})) | 
					{(32){opcode[2]}} & ((Read_data >> { Result[1:0], 3'b0}) | RF_rdata2 & ({(32){1'b1}} << {~Result[1:0], 3'b0}));//字节掩码保留寄存器的值

	assign RF_wdata = {(32){MemtoReg & (~opcode[1] |  opcode[0])}} & Read_data_masked | 
			{(32){MemtoReg & ( opcode[1] & ~opcode[0])}} & Read_data_unaligned | //访存指令的数据选取
			{(32){R_Type_mov}} & RF_rdata1  | //move指令
			{(32){R_Type_jump | J_Type}} & PC + 8 | //跳转指令
			{(32){I_Type_calc & (&opcode[3:0])}} & {Instruction[15:0], 16'd0} | //lui单独处理
			{(32){R_Type_calc | R_Type_shift | (I_Type_calc & ~(&opcode[3:0]))}} & Result;

	
endmodule
