`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ALUOP_AND 3'b000
`define ALUOP_OR 3'b001
`define ALUOP_ADD 3'b010
`define ALUOP_XOR 3'b100
`define ALUOP_NOR 3'b101
`define ALUOP_SUB 3'b110
`define ALUOP_SLT 3'b111
`define ALUOP_SLTU 3'b011

module alu(
	input  [`DATA_WIDTH - 1:0]  A,
	input  [`DATA_WIDTH - 1:0]  B,
	input  [              2:0]  ALUop,
	output                      Overflow,
	output                      CarryOut,
	output                      Zero,
	output [`DATA_WIDTH - 1:0]  Result
);
	// TODO: Please add your logic design here

	//控制信号译码
	wire op_and = ALUop == `ALUOP_AND;
	wire op_or = ALUop == `ALUOP_OR;
	wire op_add = ALUop == `ALUOP_ADD;
	wire op_sub = ALUop == `ALUOP_SUB;
	wire op_slt = ALUop == `ALUOP_SLT;
	wire op_xor = ALUop == `ALUOP_XOR;
	wire op_nor = ALUop == `ALUOP_NOR;
	wire op_sltu = ALUop == `ALUOP_SLTU;

	//临时变量
	wire [`DATA_WIDTH - 1:0] temp = ({`DATA_WIDTH{op_add}} & B) | ({`DATA_WIDTH{op_sub | op_slt | op_sltu}} & (~B));
	wire cin = op_sub | op_slt | op_sltu;
	wire [`DATA_WIDTH - 1:0] result_temp;
	wire CarryOut_temp;
	
	//计算
	wire [`DATA_WIDTH - 1:0] and_res = A & B;
	wire [`DATA_WIDTH - 1:0] or_res = A | B;
	wire [`DATA_WIDTH - 1:0] xor_res = A ^ B;
	wire [`DATA_WIDTH - 1:0] nor_res = ~(A | B);
	wire [`DATA_WIDTH - 1:0] add_res;
	assign {CarryOut_temp,add_res} = A + temp + cin;

	//选择结果
	assign result_temp = {`DATA_WIDTH{op_and}} & and_res | 
			{`DATA_WIDTH{op_or}} & or_res | 
			{`DATA_WIDTH{op_xor}} & xor_res | 
			{`DATA_WIDTH{op_nor}} & nor_res | 
			{`DATA_WIDTH{op_add | op_sub | op_slt | op_sltu}} & add_res;

	assign Overflow = (~A[`DATA_WIDTH - 1] & ~temp[`DATA_WIDTH - 1] & result_temp[`DATA_WIDTH - 1] | 
		          A[`DATA_WIDTH - 1] & temp[`DATA_WIDTH - 1] & ~result_temp[`DATA_WIDTH - 1]); 
	
	assign Result = {`DATA_WIDTH{~(op_slt | op_sltu)}} & result_temp | 
			{`DATA_WIDTH{op_slt}} &  {{`DATA_WIDTH - 1{1'b0}}, Overflow ^ (op_slt & add_res[`DATA_WIDTH - 1])} | 
			{`DATA_WIDTH{op_sltu}} &  {{`DATA_WIDTH - 1{1'b0}}, ~CarryOut_temp};
	
	assign CarryOut = (op_add & CarryOut_temp) | (op_sub & ~CarryOut_temp);

	assign Zero = (Result == 32'b0);

endmodule