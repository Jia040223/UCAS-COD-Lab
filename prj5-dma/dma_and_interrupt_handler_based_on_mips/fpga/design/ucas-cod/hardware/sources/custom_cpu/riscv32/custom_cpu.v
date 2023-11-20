`timescale 10ns / 1ns

`define Branch_or_Jump_BUS_WD    33
`define IF_TO_ID_BUS_WD  64
`define ID_TO_EX_BUS_WD  165
`define EX_TO_MEM_BUS_WD 108
`define MEM_TO_WB_BUS_WD 70
`define WB_TO_RF_BUS_WD  38
`define RDW_BUS_WD       39


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


// TODO: Please add your custom CPU code here

//声明

	wire [69:0] inst_retire;

	wire fifo_full;
	wire ID_Allow_in;
	wire EX_Allow_in;
	wire MEM_Allow_in;
	wire ws_allowin;
	wire IF_to_ID_Valid;
	wire ID_to_EX_Valid;
	wire EX_to_MEM_Valid;
	wire MEM_to_WB_Valid;
	wire ID_Valid;

	wire [`IF_TO_ID_BUS_WD - 1:0] IF_to_ID_Bus;
	wire [`ID_TO_EX_BUS_WD - 1:0] ID_to_EX_Bus;
	wire [`EX_TO_MEM_BUS_WD - 1:0] EX_to_MEM_Bus;
	wire [`MEM_TO_WB_BUS_WD - 1:0] MEM_to_WB_Bus;
	wire [`WB_TO_RF_BUS_WD - 1:0] WB_to_RegFile_Bus;
	wire [`Branch_or_Jump_BUS_WD - 1:0] Branch_or_Jump_Bus;
	wire [`RDW_BUS_WD - 1:0] rdw_EX_Bus;
	wire [`RDW_BUS_WD - 1:0] rdw_MEM_Bus;
	wire [`RDW_BUS_WD - 1:0] rdw_WB_Bus;

	wire retired;
	wire [69:0] fifo_data;
	
//例化
    	assign fifo_full = 1'b0;
	assign inst_retire = fifo_data;

	IF_State IF_State(
		.clk(                      clk),
		.rst(                      rst),
		//block signals
		.id_allowin(      ID_Allow_in),
		//branch or jump signals
		.bj_bus(Branch_or_Jump_Bus),
		.id_valid(            ID_Valid),
		//to id
		.if_to_id_valid(IF_to_ID_Valid),
		.if_to_id_bus(    IF_to_ID_Bus),
		//memory interface
		//Instruction request channel
		.pc(                        PC),
		.Inst_Req_Valid(Inst_Req_Valid),
		.Inst_Req_Ready(Inst_Req_Ready),
		//Instruction response channel
		.Instruction(      Instruction),
		.Inst_Valid(        Inst_Valid),
		.Inst_Ready(        Inst_Ready)      
	);
	
	ID_State ID_State(
		.clk(                      clk),
		.rst(                      rst),
		//allowin
		.EX_Allow_in(        EX_Allow_in),
		.ID_Allow_in(        ID_Allow_in),
		//from if
		.IF_to_ID_Valid(IF_to_ID_Valid),
		.IF_to_ID_Bus(    IF_to_ID_Bus),
		//to ex
		.ID_to_EX_Valid(ID_to_EX_Valid),
		.ID_to_EX_Bus(    ID_to_EX_Bus),
		//to rf: from WB
		.WB_to_RegFile_Bus(    WB_to_RegFile_Bus),
		//RAW signals: form EX, MEM, WB
		.rdw_EX_Bus(        rdw_EX_Bus),
		.rdw_MEM_Bus(      rdw_MEM_Bus),
		.rdw_WB_Bus(        rdw_WB_Bus),
		//to if
		.to_IF_Valid(         ID_Valid),
		.Branch_or_Jump_Bus(Branch_or_Jump_Bus)		
	);
	
	EX_State EX_State(
		.clk(                        clk),
		.rst(                        rst),
		//allowin
		.MEM_Allow_in(        MEM_Allow_in),
		.EX_Allow_in(          EX_Allow_in),
		//from id
		.ID_to_EX_Valid(  ID_to_EX_Valid),
		.ID_to_EX_Bus(      ID_to_EX_Bus),
		//to mem
		.EX_to_MEM_Valid(EX_to_MEM_Valid),
		.EX_to_MEM_Bus(    EX_to_MEM_Bus),
		//mem
		.Address(                Address),
		.MEMWrite(              MemWrite),
		.Write_data(          Write_data),
		.Write_strb(          Write_strb),
		.MEMRead(                MemRead),
		.MEM_Req_Ready(    Mem_Req_Ready),
		//rdw to id
		.rdw_EX_Bus(          rdw_EX_Bus)
	);
	
	MEM_State MEM_State(
		.clk(                        clk),
		.rst(                        rst),
		//allowin
		.WB_Allow_in(          WB_Allow_in),
		.MEM_Allow_in(        MEM_Allow_in),
		//from ex
		.EX_to_MEM_Valid(EX_to_MEM_Valid),
		.EX_to_MEM_Bus(    EX_to_MEM_Bus),
		//to wb
		.MEM_to_WB_Valid(MEM_to_WB_Valid),
		.MEM_to_WB_Bus(    MEM_to_WB_Bus),
		//mem
		.Read_data(            Read_data),
		.Read_data_Valid(Read_data_Valid),
		.Read_data_Ready(Read_data_Ready), 
		//rdw to id/ex
		.rdw_MEM_Bus(        rdw_MEM_Bus)
	);
	
	WB_State WB_State(
		.clk(                        clk),
		.rst(                        rst),
		.fifo_full(            fifo_full),
		//allowin
		.WB_Allow_in(          WB_Allow_in),
		//from mem
		.MEM_to_WB_Valid(MEM_to_WB_Valid),
		.MEM_to_WB_Bus(    MEM_to_WB_Bus),
		//to rf
		.WB_to_RegFile_Bus(WB_to_RegFile_Bus),
		//rdw to id
		.rdw_WB_Bus(          rdw_WB_Bus),
		//to fifo
		.retired(                retired),
		.fifo_data(            fifo_data)
	);


	assign inst_retire = fifo_data;


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
		end else if (Inst_Valid & Inst_Ready) begin
			inst_cnt <= inst_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_1 = inst_cnt;

	//读内存计数器
	reg  [31:0] mr_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			mr_cnt <= 32'd0;
		end else if (MemRead & Mem_Req_Ready) begin
			mr_cnt <= mr_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_2 = mr_cnt;

	//写内存计数器
	reg  [31:0] mw_cnt;
	always @ (posedge clk) begin
		if (rst) begin
			mw_cnt <= 32'd0;
		end else if (MemWrite & Mem_Req_Ready) begin
			mw_cnt <= mw_cnt + 32'd1;
		end
	end
	assign cpu_perf_cnt_3 = mw_cnt;


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

endmodule




