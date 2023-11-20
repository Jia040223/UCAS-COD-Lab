`timescale 10ns / 1ns

module custom_cpu(
	input         clk,
	input         rst,

	//Instruction request channel
	output [31:0] PC,
	output        Inst_Req_Valid,
	input         Inst_Req_Ready,

	//Instruction response channel
	input  [31:0] Instruction,
	input         Inst_Valid,
	output        Inst_Ready,

	//Memory request channel
	output [31:0] Address,
	output        MemWrite,
	output [31:0] Write_data,
	output [ 3:0] Write_strb,
	output        MemRead,
	input         Mem_Req_Ready,

	//Memory data response channel
	input  [31:0] Read_data,
	input         Read_data_Valid,
	output        Read_data_Ready,

	input         intr,

	output [31:0] cpu_perf_cnt_0,
	output [31:0] cpu_perf_cnt_1,
	output [31:0] cpu_perf_cnt_2,
	output [31:0] cpu_perf_cnt_3,
	output [31:0] cpu_perf_cnt_4,
	output [31:0] cpu_perf_cnt_5,
	output [31:0] cpu_perf_cnt_6,
	output [31:0] cpu_perf_cnt_7,
	output [31:0] cpu_perf_cnt_8,
	output [31:0] cpu_perf_cnt_9,
	output [31:0] cpu_perf_cnt_10,
	output [31:0] cpu_perf_cnt_11,
	output [31:0] cpu_perf_cnt_12,
	output [31:0] cpu_perf_cnt_13,
	output [31:0] cpu_perf_cnt_14,
	output [31:0] cpu_perf_cnt_15,

	output [69:0] inst_retire
);

/* The following signal is leveraged for behavioral simulation, 
* which is delivered to testbench.
*
* STUDENTS MUST CONTROL LOGICAL BEHAVIORS of THIS SIGNAL.
*
* inst_retired (70-bit): detailed information of the retired instruction,
* mainly including (in order) 
* { 
*   reg_file write-back enable  (69:69,  1-bit),
*   reg_file write-back address (68:64,  5-bit), 
*   reg_file write-back data    (63:32, 32-bit),  
*   retired PC                  (31: 0, 32-bit)
* }
*
*/
  	wire [69:0] inst_retire;

// TODO: Please add your custom CPU code here

//声明与宏定义
	reg [8:0] current_state;
	reg [8:0] next_state;

	localparam INIT	=9'b000000001;
	localparam IF	=9'b000000010;
	localparam IW	=9'b000000100;
	localparam ID	=9'b000001000;
	localparam EX	=9'b000010000;
	localparam ST	=9'b000100000;
	localparam LD	=9'b001000000;
	localparam RDW	=9'b010000000;
	localparam WB	=9'b100000000;

	//Instruction Decode
	reg  [31:0] reg_Instruction;
	wire [6:0]  funct7;
	wire [4:0]  rs2;
	wire [4:0]  rs1;
	wire [2:0]  funct3;
	wire [4:0]  rd;
	wire [6:0]  opcode;
	wire [31:0] imm;

	wire OP_IMM;
	wire LUI;
	wire AUIPC;
	wire OP_REG;
	wire JAL;
	wire JALR;
	wire BRANCH;
	wire Branch_or_not;
	wire LOAD;
	wire STORE;
	wire MULTIPLE;

	wire R_Type;
	wire I_Type;
	wire S_Type;
	wire B_Type;
	wire U_Type;
	wire J_Type;

	//Control Signal 
	wire Branch,MemtoReg,ALUEn,ShiftEn,MULEn,ALUSrc,ShiftSrc,RF_wen;

	//PC
	reg  [31:0] PC;
	reg  [31:0] PC_normal;

	//register
	wire [31:0] 	wire_RF_rdata1;
	wire [31:0] 	wire_RF_rdata2;
	reg  [31:0] 	RF_rdata1;
	reg  [31:0] 	RF_rdata2;
	wire [4:0]	RF_waddr;
	wire [31:0]	RF_wdata;

	//ALU and Result
	wire [31:0]     ALU_A;
	wire [31:0]	ALU_B;
	wire [2:0]	ALUop;
	wire [1:0]	Shiftop;
	wire [31:0]	ALUResult,ShifterResult;
	wire [31:0]	MULResult;
	wire 		Overflow,CarryOut,Zero;
	reg  [31:0]	Result;

	//Memory
	reg  [31:0]	Read_data_reg;

	wire [31:0]	Read_data_shifted;
	wire [31:0]	Read_data_masked;
	wire 		Read_data_sign_bit;
	wire [31:0]	Read_data_unaligned;



//三段式状态转移状态机(FSM)
	always @ (posedge clk) begin
		if (rst) begin
			current_state <= INIT;
		end else begin
			current_state <= next_state;
		end
	end

	//FSM第二段
	always @(*) begin
		case (current_state)
			INIT: next_state <= IF;
			IF: begin
				if (Inst_Req_Ready) begin
					next_state <= IW;
				end 
				else begin
					next_state <= IF;
				end
			end
			IW: begin
				if (Inst_Valid) begin
					next_state <= ID;
				end 
				else begin
					next_state <= IW;
				end
			end
			ID: next_state <= EX;
			EX: begin
			 	if (R_Type | I_Type & ~LOAD | U_Type | J_Type) begin
			 		next_state <= WB;
			 	end 
				else if (LOAD) begin
			 		next_state <= LD;
			 	end 
				else if (S_Type) begin
					next_state <= ST;
				end 
				else if (B_Type) begin
			 		next_state <= IF;
				end	
				else begin
					next_state <= INIT;
				end
			end
			ST: begin
				if (Mem_Req_Ready) begin
					next_state <= IF;
				end else begin
					next_state <= ST;
				end
			end
			LD: begin
				if (Mem_Req_Ready) begin
					next_state <= RDW;
				end else begin
					next_state <= LD;
				end
			end
			RDW: begin
				if (Read_data_Valid) begin
					next_state <= WB;
				end else begin
					next_state <= RDW;
				end
			end
			WB: next_state <= IF;
			default: next_state <= INIT;
		endcase
	end

	//FSM第三段
	//PC
	always @(posedge clk) begin
		if (current_state == IW && Inst_Valid) begin
			PC_normal <= ALUResult; //ALU算出的PC+4
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			PC <= 32'd0;
		end 
		else if (current_state == EX) begin
			if (JAL) begin
				PC <= Result; // ID阶段算出的PC(复用ALU)
			end 
			else if (JALR) begin
				PC <= Result & {~31'b0, 1'b0};	// ID阶段算出的PC(末尾清0)
			end 
			else if (Branch_or_not) begin //branch
				PC <= Result; // ID阶段算出的PC
			end
			else begin
				PC <= PC_normal;
			end
		end
	end


	//reg_Instruction
	always @(posedge clk) begin
		if (current_state == IW && Inst_Valid) begin
			reg_Instruction <= Instruction;
		end
	end


	//register
	always @(posedge clk) begin
		if (current_state == ID) begin
			RF_rdata1 <= wire_RF_rdata1;
			RF_rdata2 <= wire_RF_rdata2;
		end
	end


	//Result
	always @(posedge clk) begin
		if ((current_state == EX) || (current_state == ID)) begin
			Result <= {(32){ALUEn}}  &  ALUResult | 
				 {(32){ShiftEn}} &  ShifterResult | 
				 {(32){MULEn}}   &  MULResult; //Choose Result
		end
	end


	//Read_Data
	always @(posedge clk) begin
		if (current_state == RDW && Read_data_Valid) begin
			Read_data_reg <= Read_data;
		end
	end



//Performance Counter
	//周期计数器
	reg  [31:0] cycle_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			cycle_cnt <= 32'd0;
		end else begin
			cycle_cnt <= cycle_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_0 = cycle_cnt;

	//指令计数器
	reg  [31:0] inst_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			inst_cnt <= 32'd0;
		end else if (current_state == ID) begin
			inst_cnt <= inst_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_1 = inst_cnt;

	//读内存计数器
	reg  [31:0] mr_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			mr_cnt <= 32'd0;
		end else if (current_state == ID && LOAD) begin
			mr_cnt <= mr_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_2 = mr_cnt;

	//写内存计数器
	reg  [31:0] mw_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			mw_cnt <= 32'd0;
		end else if (current_state == ID && STORE) begin
			mw_cnt <= mw_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_3 = mw_cnt;

	//取指请求延误周期计数器
	reg  [31:0] inst_req_delay_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			inst_req_delay_cnt <= 32'd0;
		end else if (current_state == IF && next_state == IF) begin
			inst_req_delay_cnt <= inst_req_delay_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_4 = inst_req_delay_cnt;

	//取值延误周期计数器
	reg  [31:0] inst_delay_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			inst_delay_cnt <= 32'd0;
		end else if (current_state == IW && next_state == IW) begin
			inst_delay_cnt <= inst_delay_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_5 = inst_delay_cnt;

	//读内存请求延误周期计数器
	reg  [31:0] mr_req_delay_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			mr_req_delay_cnt <= 32'd0;
		end else if (current_state == LD && next_state == LD) begin
			mr_req_delay_cnt <= mr_req_delay_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_6 = mr_req_delay_cnt;

	//从内存获取数据延误周期计数器
	reg  [31:0] rdw_delay_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			rdw_delay_cnt <= 32'd0;
		end else if (current_state == RDW && next_state == RDW) begin
			rdw_delay_cnt <= rdw_delay_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_7 = rdw_delay_cnt;

	//写内存请求延误周期寄存器
	reg  [31:0] mw_req_delay_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			mw_req_delay_cnt <= 32'd0;
		end else if (current_state == ST && next_state == ST) begin
			mw_req_delay_cnt <= mw_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_8 = mw_req_delay_cnt;

	//分支指令计数器
	reg  [31:0] branch_inst_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			branch_inst_cnt <= 32'd0;
		end else if (current_state == ID && BRANCH) begin
			branch_inst_cnt <= branch_inst_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_9 = branch_inst_cnt;

	//跳转指令计数器
	reg  [31:0] jump_inst_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			jump_inst_cnt <= 32'd0;
		end else if (current_state == ID && (JALR || JAL)) begin
			jump_inst_cnt <= jump_inst_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_10 = jump_inst_cnt;

	//辅助周期计数器(帮助处理周期计数器溢出的问题)
	reg  [31:0] sub_cycle_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			sub_cycle_cnt <= 32'd0;
		end else if (&cycle_cnt) begin
			sub_cycle_cnt <= sub_cycle_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_11 = sub_cycle_cnt;



//其它组合逻辑
	//inst_retire
	assign inst_retire [69:69] = RF_wen;
	assign inst_retire [68:64] = RF_waddr;
	assign inst_retire [63:32] = RF_wdata;
	assign inst_retire [31: 0] = PC_normal;

	//Handshake Signal
	assign Inst_Req_Valid		= current_state == IF;
	assign Inst_Ready		= current_state == IW || current_state == INIT;
	assign MemWrite			= current_state == ST;
	assign MemRead			= current_state == LD;
	assign Read_data_Ready		= current_state == RDW || current_state == INIT;

	//Instruction Decode
	assign {funct7, rs2, rs1, funct3, rd, opcode} = reg_Instruction;

	assign OP_IMM	= opcode[6:0] == 7'b0010011;	
	assign LUI	= opcode[6:0] == 7'b0110111;
	assign AUIPC	= opcode[6:0] == 7'b0010111;
	assign OP_REG	= opcode[6:0] == 7'b0110011;
	assign JAL	= opcode[6:0] == 7'b1101111;
	assign JALR	= opcode[6:0] == 7'b1100111;
	assign BRANCH	= opcode[6:0] == 7'b1100011;
	assign LOAD	= opcode[6:0] == 7'b0000011;
	assign STORE	= opcode[6:0] == 7'b0100011;

	assign R_Type = OP_REG;
	assign I_Type = OP_IMM | JALR | LOAD; //JALR指令和LOAD类型的指令是I_Type的格式
	assign S_Type = STORE;
	assign B_Type = BRANCH;
	assign U_Type = LUI | AUIPC; //LUI和AUIPC是U_Type的格式
	assign J_Type = JAL;

	//MULTIPLY Instruction
	assign MULTIPLE = OP_REG & funct7[0];

	//Control Signal
	assign Branch 	= B_Type;
	assign MemtoReg	= LOAD;
	assign ALUSrc	= I_Type | S_Type | U_Type; //I_Type和S_Type的ALU或Shifter操作来源是立即数
	assign ShiftSrc = I_Type | S_Type; 
	assign RF_wen	= (current_state == WB) & (J_Type | I_Type | R_Type | U_Type); //只有S_Type和B_Type不用写回

	assign ALUEn	= (OP_REG | OP_IMM) & (~MULTIPLE) & (funct3[1] | ~funct3[0]) | JALR | LOAD | S_Type | B_Type |
			  (current_state == ID); //ID阶段Result需要对ALU的结果进行选择
	assign ShiftEn	= (OP_REG | OP_IMM) & (~MULTIPLE) & (~funct3[1] & funct3[0]) & 
		          ~(current_state == ID); //ID阶段Result需要对ALU的结果进行选择
	assign MULEn 	= MULTIPLE & 
	                  ~(current_state == ID);//ID阶段Result需要对ALU的结果进行选择


	//Extend Immediate (要实现的RISCV32中的指令的立即数扩展均是有符号扩展,包括与操作，或操作，异或操作)
	assign imm = {(32){U_Type}} & {reg_Instruction[31:12], 12'b0} | 
		     {(32){J_Type}} & {{(12){reg_Instruction[31]}}, reg_Instruction[19:12], reg_Instruction[20], reg_Instruction[30:21],1'b0} |
		     {(32){B_Type}} & {{(20){reg_Instruction[31]}}, reg_Instruction[7], reg_Instruction[30:25], reg_Instruction[11:8], 1'b0} | 
		     {(32){I_Type}} & {{(20){reg_Instruction[31]}}, reg_Instruction[31:20]} | 
		     {(32){S_Type}} & {{(20){reg_Instruction[31]}}, reg_Instruction[31:25], reg_Instruction[11:7]};


	//Branch_or_not
	assign Branch_or_not = (Zero ^ funct3[2] ^ funct3[0]) & Branch;


	//Registers
	reg_file Registers(
		.clk	(clk),
		.waddr	(RF_waddr),
		.raddr1	(rs1),
		.raddr2	(rs2),
		.wen	(RF_wen),
		.wdata	(RF_wdata),
		.rdata1	(wire_RF_rdata1),
		.rdata2	(wire_RF_rdata2)
	);

	assign RF_waddr = rd;


	//ALU
	assign ALU_A = {(32){(current_state == IW && Inst_Valid)}} & PC | //算PC+4
			{(32){current_state == ID}} & (JALR ? wire_RF_rdata1 : PC) | //算跳转和分支指令的目标地址 
			{(32){current_state == EX}} & (U_Type ? PC :RF_rdata1);//AUIPC指令的操作数之一为PC

	assign ALU_B = {(32){(current_state == IW && Inst_Valid)}} & {29'b0, 3'b100} | //算PC+4
			{(32){current_state == ID}} & imm | //算跳转和分支指令的目标地址
			{(32){current_state == EX}} & (ALUSrc ? imm :RF_rdata2);


	assign ALUop = (current_state == EX) ? 
			({(3){OP_IMM | OP_REG}} & {
				(funct3 == 3'b100) | (funct3 == 3'b010) | (funct3 == 3'b000 && funct7[5] && opcode[5]),	//xor slt sub类型操作首位为1，其它为0
				~funct3[2],										//and, or, xor类型操作第二位为0，其它为1
				funct3[1] & ~(funct3[0] & funct3[2])							//or, slt, sltu类型操作第三位为1，其它为0
			} | 
			{(3){STORE | LOAD | JALR | U_Type}} & 3'b010 |						//add 010
	  		{(3){BRANCH}} & {~funct3[1], 1'b1, funct3[2]})					//sub 110 slt 111 sltu 011
			: 010;


	alu ALU(
		.A		(ALU_A),
		.B		(ALU_B),
		.ALUop		(ALUop),
		.Overflow	(Overflow),
		.CarryOut	(CarryOut),
		.Zero		(Zero),
		.Result		(ALUResult)
	);


	//Shifter
	assign Shiftop = {funct3[2],funct7[5]}; //funct3[2]代表左移右移,funct7[5]代表逻辑移位还是算术移位

	shifter Shifter(
		.A		(RF_rdata1),
		.B		(ShiftSrc ? imm[4:0] : RF_rdata2[4:0]), //移位对32取模
		.Shiftop	(Shiftop),
		.Result		(ShifterResult)
	);


	//MULTIPLY
	assign MULResult = RF_rdata1 * RF_rdata2;



	//Write
	assign Address 		= Result & ~32'b11; //对齐
	assign Write_data	= RF_rdata2 << {Result[1:0], 3'b0};
	assign Write_strb	= {( Result[1] | funct3[1]) & ( Result[0] | funct3[0] | funct3[1]),
				   ( Result[1] | funct3[1]) & (~Result[0] | funct3[0] | funct3[1]),
				   (~Result[1] | funct3[1]) & ( Result[0] | funct3[0] | funct3[1]),
				   (~Result[1] | funct3[1]) & (~Result[0] | funct3[0] | funct3[1])};

	//Write Back
	assign Read_data_shifted 	= Read_data_reg >> {Result[1:0], 3'b0};
	assign Read_data_sign_bit 	= Read_data_shifted[funct3[1:0]==2'b01 ? 15 : 7];//符号位

	assign Read_data_masked 	= Read_data_shifted & {{(16){funct3[1]}}, {(8){funct3[0] | funct3[1]}}, {(8){1'b1}}} |
				         {(32){~funct3[2] & Read_data_sign_bit}} & ~{{(16){funct3[1]}}, {(8){funct3[0] | funct3[1]}}, {(8){1'b1}}}; 
					//字节掩码进行数据选择并进行符号位或者零扩展

	assign RF_wdata 		= {(32){LUI}}		& imm | 
					  {(32){AUIPC}}		& Result | //避免使用额外的加法器,AUIPC指令的结果也使用ALU进行计算
					  {(32){JAL | JALR}}	& PC_normal | //PC_normal存的是PC+4
					  {(32){LOAD}}		& Read_data_masked | 
					  {(32){OP_REG | OP_IMM}}	& Result;


endmodule
