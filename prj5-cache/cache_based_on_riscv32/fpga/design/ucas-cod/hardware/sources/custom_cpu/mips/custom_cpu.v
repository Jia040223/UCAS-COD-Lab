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
	wire			RF_wen;
	wire [4:0]		RF_waddr;
	wire [31:0]		RF_wdata;

	reg [31:0] reg_Instruction;


	wire [5:0] opcode;
	wire [4:0] rs;
	wire [4:0] rt;
	wire [4:0] rd;
	wire [4:0] shamt;
	wire [5:0] func;

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

	wire RegDst,Branch,MemtoReg,ALUEn,ShiftEn,ALU_IM,Shift_IM;

	// sign extend
	reg [31:0] SignExtend;
	//zero extend for I-Type andi, ori, xori
	reg [31:0] ZeroExtend;
	//Select
	wire [31:0] ExtendedImm;

	//PC
	reg [31:0] PC;
	reg [31:0] PC_normal;

	//Registers
	reg  [31:0] RF_rdata1;
	reg  [31:0] RF_rdata2;
	wire [31:0] wire_RF_rdata1;
	wire [31:0] wire_RF_rdata2;

	//ALU && Shifter
	wire [2:0] ALUop;
	wire [1:0] Shiftop;

	wire Overflow;
	wire CarryOut,Zero;
	reg  [31:0] Result;
	wire [31:0] ALUResult;
	wire [31:0] ShifterResult;

	wire [31:0] ALU_A;
	wire [31:0] ALU_B;

	//WB
	reg [31:0] Read_data_reg;

	wire [31:0] Read_data_shifted;
	wire [31:0] Read_data_masked;
	wire Read_data_sign; 
	wire [31:0] Read_data_unaligned;

	//INTR
	reg intr_en;

	//eret指令
    	wire ERET;

	//EPC(保存PC值)
	reg [31:0] EPC;

	//FSM
	reg [9:0] current_state;
	reg [9:0] next_state;

	localparam INIT	=10'b0000000001;
	localparam IF	=10'b0000000010;
	localparam IW	=10'b0000000100;
	localparam ID	=10'b0000001000;
	localparam EX	=10'b0000010000;
	localparam ST	=10'b0000100000;
	localparam LD	=10'b0001000000;
	localparam RDW	=10'b0010000000;
	localparam WB	=10'b0100000000;
	localparam INTR =10'b1000000000; //中断处理



//三段式状态转移状态机(FSM)
	always @ (posedge clk) begin
		if(rst) begin
			current_state <= INIT;
		end else begin
			current_state <= next_state;
		end
	end


	always @(*) begin
		case (current_state)
			INIT: next_state <= IF;
			IF: begin
				if (intr & !intr_en) begin //intr为1，且不处于中断处理状态，则转移到INTR状态
                    			next_state <= INTR;
                		end
				else if (Inst_Req_Ready) begin
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
			ID: begin
				if (|reg_Instruction) begin
					next_state <= EX;
				end else begin
					next_state <= IF;
				end
			end
			EX: begin
				if (ERET) begin //ERET也会转移到IF(没有执行阶段)
					next_state <= IF;
				end
			 	else if (R_Type | I_Type_calc | J_Type & opcode[0]) begin
			 		next_state <= WB;
			 	end 
				else if (I_Type_mr) begin
			 		next_state <= LD;
			 	end 
				else if (I_Type_mw) begin
					next_state <= ST;
				end 
		
				else begin
			 		next_state <= IF;
			 	end	
			end
			ST: begin
				if (Mem_Req_Ready) begin
					next_state <= IF;
				end 
				else begin
					next_state <= ST;
				end
			end
			LD: begin
				if (Mem_Req_Ready) begin
					next_state <= RDW;
				end 
				else begin
					next_state <= LD;
				end
			end
			RDW: begin
				if (Read_data_Valid) begin
					next_state <= WB;
				end 
				else begin
					next_state <= RDW;
				end
			end
			WB:      next_state <= IF;
			INTR:    next_state <= IF;
			default: next_state <= INIT;
		endcase
	end

	// INTR
	always @(posedge clk) begin
		if (rst) begin
			intr_en <= 1'b0;
		end
		else if ((current_state == EX) & ERET) begin //完成ERET指令，则intr_en赋值0
			intr_en <= 1'b0;
		end
		else if (current_state == INTR) begin //进入中断处理，将intr_en赋值1
			intr_en <= 1'b1; 
		end
	end


	//EPC(保存PC值)
	always @(posedge clk) begin
		if (current_state == INTR) begin //进入中断处理，保存PC值
			EPC <= PC;
		end
	end


	//reg_Instruction
	always @(posedge clk) begin
		if (current_state == IW && Inst_Valid) begin
			reg_Instruction <= Instruction;
		end
	end


	//EXTEND_IMM
	always @(posedge clk) begin
		if (current_state == ID) begin
			SignExtend <= {{(16){reg_Instruction[15]}}, reg_Instruction[15:0]};
			ZeroExtend <= {16'b0, reg_Instruction[15:0]};
		end
	end


	//PC
	always @(posedge clk) begin
		if (current_state == ID) begin
			PC_normal <= PC;
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			PC <= 32'd0;
		end 
		else if (current_state == INTR) begin  // 进入中断处理, PC改为0x100(中断处理程序的入口)
            		PC <= 32'h100;
        	end
		else if (current_state == IW && Inst_Valid) begin
			PC <= ALUResult;
		end 
		else if (current_state == EX) begin
			if(ERET) begin
				PC <= EPC; //ERET PC更新到保存的值
			end
			else if (R_Type_jump) begin
				PC <= RF_rdata1;
			end 
			else if (J_Type) begin
				PC <= {PC_normal[31:28], reg_Instruction[25:0], 2'b00};	
			end 
			else if ((Zero ^ (REGIMM & ~reg_Instruction[16] | 
				     I_Type_b & (opcode[0] ^ (opcode[1] & |RF_rdata1)))) & Branch) begin //branch
				PC <= Result; // ID阶段算出的PC
			end
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
			Result <= {(32){ALUEn}} & ALUResult | 
				 {(32){ShiftEn}} & ShifterResult; //Choose Result
		end
	end


	//WB
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
		end else if (current_state == ID && I_Type_mr) begin
			mr_cnt <= mr_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_2 = mr_cnt;

	//写内存计数器
	reg  [31:0] mw_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			mw_cnt <= 32'd0;
		end else if (current_state == ID && I_Type_mw) begin
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
		end else if (current_state == ID && (I_Type_b || REGIMM)) begin
			branch_inst_cnt <= branch_inst_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_9 = branch_inst_cnt;

	//跳转指令计数器
	reg  [31:0] jump_inst_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			jump_inst_cnt <= 32'd0;
		end else if (current_state == ID && (R_Type_jump || J_Type)) begin
			jump_inst_cnt <= jump_inst_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_10 = jump_inst_cnt;

	//辅助周期计数器(帮助处理周期计数器溢出的问题)
	reg  [31:0] sub_cycle_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			sub_cycle_cnt <= 32'd0;
		end else if (&cycle_cnt) begin //存周期数的高位
			sub_cycle_cnt <= sub_cycle_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_11 = sub_cycle_cnt;



//其它组合逻辑
	//Handshake Signal
	assign Inst_Req_Valid		= current_state == IF & ~(intr & ~intr_en); //保证intr拉高的那一个clk内Inst_Req_Valid没有效
	assign Inst_Ready		= current_state == IW || current_state == INIT;
	assign MemWrite			= current_state == ST;
	assign MemRead			= current_state == LD;
	assign Read_data_Ready		= current_state == RDW || current_state == INIT;

	//Instruction Decode
	assign {opcode,rs,rt,rd,shamt,func} = reg_Instruction;

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

	//eret 指令
	assign ERET = opcode[4];

	//Control Signal
	assign RegDst 	= R_Type;
	assign Branch 	= REGIMM | I_Type_b;
	assign ALUEn	= R_Type_calc | REGIMM | I_Type_b | I_Type_calc | I_Type_mr | I_Type_mw | (current_state == IF) | (current_state == ID);
	assign ShiftEn	= R_Type_shift; 
	assign ALU_IM	= I_Type_calc | I_Type_mr | I_Type_mw; //立即数计算
	assign Shift_IM = ~func[2]; //立即数移位
	assign MemtoReg = I_Type_mr;
	assign RF_wen	= (current_state==WB) & (R_Type & 
			~(R_Type_mov & (func[0] ^ (|RF_rdata2))) & //move指令条件满足才写
			~(R_Type_jump & ~func[0])) | //jr指令RF_wen不能位1
			J_Type & opcode[0] | I_Type_calc | I_Type_mr; 


	//Select EXTEND_IMM
	assign ExtendedImm = opcode[5:2] == 4'b0011 ? ZeroExtend : SignExtend;
	

	//Registers
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
		.rdata1	(wire_RF_rdata1),
		.rdata2	(wire_RF_rdata2)
	);


	//ALUop && Shiftop
	assign ALUop = (current_state == EX) ?
			({(3){R_Type_calc}} & {func[1] & ~(func[3] & func[0]), ~func[2], func[3] & ~func[2] & func[1] | func[2] & func[0]} | 
			{(3){I_Type_calc}} & {opcode[1] & ~(opcode[3] & opcode[0]), ~opcode[2],opcode[3] & ~opcode[2] & opcode[1] | opcode[2] & opcode[0]} | 
			{(3){REGIMM}} | 
			{(3){I_Type_b}}	 & {2'b11, opcode[1]} | // slt 111 sub 110
	  		{(3){I_Type_mr | I_Type_mw}} & 3'b010) 
			: 3'b010;

	assign Shiftop = func[1:0];


	//ALU
	assign ALU_A = {(32){(current_state == IW && Inst_Valid) | (current_state == ID)}} & PC |
			{(32){current_state == EX}} & RF_rdata1;
	assign ALU_B = {(32){(current_state == IW && Inst_Valid)}} & {29'b0, 3'b100} |
			{(32){current_state == ID}} & {{{(14){reg_Instruction[15]}}, reg_Instruction[15:0]}, 2'b00} | 
			{(32){current_state == EX}} & (ALU_IM ? ExtendedImm : REGIMM ? 32'b0 :RF_rdata2);

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
	shifter Shifter(
		.A		(RF_rdata2),
		.B		(Shift_IM ? shamt : RF_rdata1[4:0]),//移位对32取模
		.Shiftop	(Shiftop),
		.Result		(ShifterResult)
	);

	
	//Memory_Write
	assign Address		= Result & ~32'b11; //对齐
	assign Write_data	= (opcode[2:0] == 3'b010) ? RF_rdata2 >> {~Result[1:0], 3'b0} : RF_rdata2 << {Result[1:0], 3'b0}; //除swl外移位规则相同

	assign Write_strb 	= {(4){~opcode[2] & opcode[1] & ~opcode[0]}} & {Result[1] & Result[0], Result[1], Result[1] | Result[0], 1'b1} | //swl
				{(4){ opcode[2] & opcode[1] & ~opcode[0]}} & {1'b1, ~(Result[1] & Result[0]), ~Result[1], ~(Result[1] | Result[0])} | //swr
			  	{(4){~opcode[1] | opcode[0]}} &{( Result[1] | opcode[1]) & ( Result[0] | opcode[0]),
						   	 	( Result[1] | opcode[1]) & (~Result[0] | opcode[0]),
						   	 	(~Result[1] | opcode[1]) & ( Result[0] | opcode[0]),
						     		(~Result[1] | opcode[1]) & (~Result[0] | opcode[0])};


	//Memory_Read
	assign Read_data_shifted 	= Read_data_reg >> {Result[1:0], 3'b0};
	assign Read_data_sign 		= Read_data_shifted[(opcode[1:0]==2'b01) ? 15 : 7];//符号位

	assign Read_data_masked 	= Read_data_shifted & {{(16){opcode[1]}}, {(8){opcode[0]}}, {(8){1'b1}}} | 
					{(32){~opcode[2] & Read_data_sign}} & ~{{(16){opcode[1]}}, {(8){opcode[0]}}, {(8){1'b1}}};//字节掩码进行有符号扩展

	assign Read_data_unaligned 	= {(32){~opcode[2]}} & ((Read_data_reg << {~Result[1:0], 3'b0}) | RF_rdata2 & ({(32){1'b1}} >> { Result[1:0], 3'b0})) | 
					{(32){opcode[2]}} & ((Read_data_reg >> { Result[1:0], 3'b0}) | RF_rdata2 & ({(32){1'b1}} << {~Result[1:0], 3'b0}));//字节掩码保留寄存器的值

	assign RF_wdata = {(32){MemtoReg & (~opcode[1] |  opcode[0])}} & Read_data_masked | 
			{(32){MemtoReg & ( opcode[1] & ~opcode[0])}} & Read_data_unaligned | //访存指令的数据选取
			{(32){R_Type_mov}} & RF_rdata1  | //move指令
			{(32){R_Type_jump | J_Type}} & PC_normal + 4 | //跳转指令
			{(32){I_Type_calc & (&opcode[3:0])}} & {reg_Instruction[15:0], 16'd0} | //lui单独处理
			{(32){R_Type_calc | R_Type_shift | (I_Type_calc & ~(&opcode[3:0]))}} & Result;

	
endmodule
