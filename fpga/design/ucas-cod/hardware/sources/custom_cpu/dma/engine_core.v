`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Xu Zhang (zhangxu415@mails.ucas.ac.cn)
// 
// Create Date: 06/14/2018 11:39:09 AM
// Design Name: 
// Module Name: dma_core
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module engine_core #(
	parameter integer  DATA_WIDTH       = 32
)
(
	input    clk,
	input    rst,
	
	output [31:0]       src_base,
	output [31:0]       dest_base,
	output [31:0]       tail_ptr,
	output [31:0]       head_ptr,
	output [31:0]       dma_size,
	output [31:0]       ctrl_stat,

	input  [31:0]	    reg_wr_data,
	input  [ 5:0]       reg_wr_en,
  
	output              intr,
  
	output [31:0]       rd_req_addr,
	output [ 4:0]       rd_req_len,
	output              rd_req_valid,
	
	input               rd_req_ready,
	input  [31:0]       rd_rdata,
	input               rd_last,
	input               rd_valid,
	output              rd_ready,
	
	output [31:0]       wr_req_addr,
	output [ 4:0]       wr_req_len,
	output              wr_req_valid,
	input               wr_req_ready,
	output [31:0]       wr_data,
	output              wr_valid,
	input               wr_ready,
	output              wr_last,
	
	output              fifo_rden,
	output [31:0]       fifo_wdata,
	output              fifo_wen,
	
	input  [31:0]       fifo_rdata,
	input               fifo_is_empty,
	input               fifo_is_full
);
	// TODO: Please add your logic design here


// 声明和宏定义
	//  ctrl & state reg
	reg [31:0] src_base;
	reg [31:0] dest_base;
	reg [31:0] tail_ptr;
	reg [31:0] head_ptr;
	reg [31:0] dma_size; 
	reg [31:0] ctrl_stat;

	// en
	wire en;

	// burst control
	wire [31:0] burst_total_num;
	wire [4:0] last_burst;
	wire [31:0] burst_normal_num;

	wire rd_dma_finished, wr_dma_finished;
	wire[2:0] last_burst_len;

	// read state regs
	reg [3:0] rd_current_state;
	reg [3:0] rd_next_state;

	// write state regs
	reg [3:0] wr_current_state;
	reg [3:0] wr_next_state;


	// read mem
	reg [31:0] rd_burst_num;

	// write mem
	reg [31:0] wr_burst_num;
	reg [2:0] wr_size;

	// read fifo
	reg [31:0] reg_fifo_rdata;

	//RD状态机states宏定义(常量)
	localparam IDLE = 4'b0001;
	localparam REQ  = 4'b0010;
	localparam RW   = 4'b0100;
	localparam FIFO = 4'b1000;

	//独热码下表宏定义(常量)
	localparam isIDLE = 0;
	localparam isREQ  = 1;
	localparam isRW   = 2;
	localparam isFIFO = 3;


//状态机
	// --- read状态机 ---
	// 第一段
	always @(posedge clk) begin
		if (rst) begin
			rd_current_state <= IDLE;
		end
		else begin
			rd_current_state <= rd_next_state;
		end
	end

	// 第二段
	always @(*) begin
		case (rd_current_state)
			IDLE: begin
				if (en & wr_current_state[isIDLE] & (head_ptr != tail_ptr) & !rd_dma_finished & fifo_is_empty) begin //fifo为空才能开始写入!!!!
					rd_next_state = REQ;  //tail_ptr != head_ptr时，DMA引擎自动启动
				end
				else begin
					rd_next_state = IDLE;
				end
			end
			REQ: begin
				if (fifo_is_full) begin
					rd_next_state = IDLE;  //fifo满了停止写入，读引擎停止工作，写引擎开始工作!!!!
				end
				else if (rd_req_ready & rd_req_valid) begin //握手成功
					rd_next_state = RW;
				end
				else begin
					rd_next_state = REQ;
				end
			end
			RW: begin
				if (rd_valid & rd_ready & rd_last) begin //握手成功+本轮burst的最后一次读完成
					rd_next_state = REQ;
				end
				else begin
					rd_next_state = RW;
				end
			end
			default: rd_next_state = IDLE;
		endcase
	end


	// --- write状态机 ---	
	// 第一段
	always @(posedge clk) begin
		if (rst) begin
			wr_current_state <= IDLE;
		end
		else begin
			wr_current_state <= wr_next_state;
		end
	end

	// 第二段
	always @(*) begin
		case (wr_current_state)
			IDLE: begin
				if (en & rd_current_state[isIDLE] & !(fifo_is_full & wr_dma_finished) & !wr_dma_finished & fifo_is_full) begin //fifo满了才能进行读!!!!
					wr_next_state = REQ; //tail_ptr != head_ptr时，DMA引擎自动启动
				end
				else begin
					wr_next_state = IDLE;
				end
			end
			REQ: begin
				if (wr_dma_finished | fifo_is_empty) begin //fifo读空后 or 一次DMA子缓冲区的全部读写完成
					wr_next_state = IDLE; 
				end
				else if (wr_req_ready & wr_req_valid) begin //握手完成
					wr_next_state = FIFO;
				end
				else begin
					wr_next_state = REQ;
				end
			end
			RW: begin
				if (wr_ready & wr_last | fifo_is_empty) begin //fifo读空后 or 握手完成且本次写完成
					wr_next_state = REQ;
				end
				else if (wr_ready & !fifo_is_empty) begin //握手完成 但本次写未完成(fifo不空)
					wr_next_state = FIFO;
				end
				else begin
					wr_next_state = RW;
				end
			end
			FIFO: begin
				wr_next_state = RW; //FIFO阶段寄存器存进数据，下一个状态为RW，进行写操作(4个字节)
			end
			default: begin
				wr_next_state = IDLE;
			end
		endcase
	end


	//根据reg_wr_en进行DMA的寄存器写
	always @(posedge clk) begin
		if (reg_wr_en[0]) begin
			src_base <= reg_wr_data;
		end
	end
	always @(posedge clk) begin
		if (reg_wr_en[1]) begin
			dest_base <= reg_wr_data;
		end
	end
	always @(posedge clk) begin
		if (reg_wr_en[2]) begin
			tail_ptr <= reg_wr_data;
		end
		else if (rd_dma_finished & wr_dma_finished & wr_current_state[isIDLE] & rd_current_state[isIDLE]) begin
			tail_ptr <= tail_ptr + dma_size; //一次DMA子缓冲区的读写全部完成，更新尾指针
		end
	end
	always @(posedge clk) begin
		if (reg_wr_en[3]) begin
			head_ptr <= reg_wr_data;
		end
	end
	always @(posedge clk) begin
		if (reg_wr_en[4]) begin
			dma_size <= reg_wr_data;
		end
	end
	always @(posedge clk) begin
		if (reg_wr_en[5]) begin
			ctrl_stat <= reg_wr_data;
		end
		else if (en & rd_dma_finished & wr_dma_finished & wr_current_state[isIDLE] & rd_current_state[isIDLE]) begin
			ctrl_stat[31] <= 1'b1;  //一次DMA子缓冲区的读写全部完成，更新ctrl_stat[31](中断标志位)
		end
	end


	// read mem
	always @(posedge clk) begin
		if (rst) begin  // rst复位
			rd_burst_num <= 0;
		end
		else if (rd_current_state[isIDLE] & wr_current_state[isIDLE] & en & (head_ptr != tail_ptr) & rd_dma_finished & wr_dma_finished) begin 
			rd_burst_num <= 0;  //当一次DMA子缓冲区的读写全部完成后，开启下一轮DMA子缓冲区读写时，burst计数器清0
		end
		else if (rd_current_state[isRW] & rd_valid & rd_last) begin  // 一次burst的rd完成
			rd_burst_num <= rd_burst_num + 1;
		end
	end

	// read fifo
	always @(posedge clk) begin
		if (wr_current_state[isFIFO]) begin  // FIFO阶段寄存器存入fifo_rdata，RW进行写
			reg_fifo_rdata <= fifo_rdata; 
		end
	end

	// write memory
	always @(posedge clk) begin
		if (rst) begin  // rst复位
			wr_burst_num <= 0;
		end
		else if(wr_current_state[isIDLE] & rd_current_state[isIDLE] & en & ~intr & (head_ptr != tail_ptr) & rd_dma_finished & wr_dma_finished) begin 
			wr_burst_num <= 0; //当一次DMA子缓冲区的读写全部完成后，开启下一轮DMA子缓冲区读写时，burst计数器清0
		end
		else if (wr_current_state[isRW] & wr_ready & wr_last) begin  // 一次burst的wr完成
			wr_burst_num <= wr_burst_num + 1;
		end
	end

	
	//wr_size
	always @(posedge clk) begin
		if (rst) begin  // rst复位
			wr_size <= 3'b0;
		end
		else if(wr_current_state[isREQ]) begin //write state为REQ时重新计数(下一轮burst的wr)
			wr_size <= 3'b0;
		end
		else if (wr_current_state[isRW] & wr_ready) begin  // 每轮传输写入4byte后, wr_size加一
			wr_size <= wr_size + 1;
		end
	end



//其它组合逻辑
	//intr
	assign intr = ctrl_stat[31];

	//en
	assign en = ctrl_stat[0];

	//判断本轮DMA子缓冲区的读写是否完成
	assign rd_dma_finished = (rd_burst_num == burst_total_num); //完成rd的burst的总数等于 需要完成的burst的总数
	assign wr_dma_finished = (wr_burst_num == burst_total_num); //完成wr的burst的总数等于 需要完成的burst的总数
	

	//DMA引擎一轮共需发起( int(N/32) + (N % 32 != 0) )次Burst传输
	assign last_burst 	= dma_size[4:0]; //(N % 32)
	assign burst_normal_num = {5'b0, dma_size[31:5]}; //前(int(N / 32))次Burst
	assign burst_total_num 	= {5'b0, dma_size[31:5]} + |last_burst; //Burst总数

	assign last_burst_len = last_burst[4:2] + |(last_burst[1:0]); //((N % 32) / 4) + ( ((N % 32) % 4) != 0)


	//rd输出
	// Handshake Signal
	assign rd_req_valid = rd_current_state[isREQ] & !fifo_is_full & !rd_dma_finished; //fifo为满，握手信号全部拉低(FIFO不接受写入)
	assign rd_ready = rd_current_state[isRW];


	//rd的addr & len
	assign rd_req_addr = src_base + tail_ptr + {rd_burst_num, 5'b0}; //DMA读操作的首地址为(src_base + tail_ptr),每次burst读入32位
	assign rd_req_len = rd_dma_finished ? {2'b0, (last_burst_len)} : 5'b111;//不是最后一次长度为32Byte(写8次)，否则写((N%32)/4) + (((N%32)%4)!=0)次.


	// write to fifo
	assign fifo_wen = rd_ready & rd_valid & !fifo_is_full; //读内存握手完成
	assign fifo_wdata = rd_rdata; 


	// read from fifo
	assign fifo_rden = wr_next_state[isFIFO]; 
	

	// write memory
	// Handshake Signal
	assign wr_req_valid = wr_current_state[isREQ] & !fifo_is_empty; //fifo为空，握手信号全部拉低(FIFO不接受读)
	assign wr_valid = wr_current_state[isRW];


	// wr的addr & len & data
	assign wr_req_addr = dest_base + tail_ptr + {wr_burst_num, 5'b0}; // DMA写操作的首地址为(dest_base + tail_ptr),每次burst读入32位
	assign wr_req_len = wr_dma_finished ? {2'b0, (last_burst_len)} : 5'b111;//不是最后一次长度为32Byte(写8次)，否则写((N%32)/4) + (((N%32)%4)!=0)次.
	assign wr_data = reg_fifo_rdata;


	//最后一次wr完成
	assign wr_last = (wr_size == wr_req_len[2:0]); //本次burst写的次数等于需要的次数


endmodule

