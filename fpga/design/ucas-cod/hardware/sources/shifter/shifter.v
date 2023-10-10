`timescale 10 ns / 1 ns

`define DATA_WIDTH 32

module shifter (
	input  [`DATA_WIDTH - 1:0] A,
	input  [              4:0] B,
	input  [              1:0] Shiftop,
	output [`DATA_WIDTH - 1:0] Result
);
	// TODO: Please add your logic code here
	assign Result =	{(`DATA_WIDTH){~Shiftop[1] & ~Shiftop[0]}} & (A<<B) |  //Logical Shift Left
			{(`DATA_WIDTH){ Shiftop[1] & ~Shiftop[0]}} & (A>>B) |  //Logical Shift Right
			{(`DATA_WIDTH){ Shiftop[1] &  Shiftop[0]}} & ((A>>B) | ~((~32'b0)>>B) & {(32){A[31]}});  //Arithmetic Shift Right

endmodule
