`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module icache_top (
	input	      clk,
	input	      rst,
	
	//CPU interface
	/** CPU instruction fetch request to Cache: valid signal */
	input         from_cpu_inst_req_valid,
	/** CPU instruction fetch request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_inst_req_addr,
	/** Acknowledgement from Cache: ready to receive CPU instruction fetch request */
	output        to_cpu_inst_req_ready,
	
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit Instruction value */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive Instruction */
	input	      from_cpu_cache_rsp_ready,

	//Memory interface (32 byte aligned address)
	/** Cache sending memory read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address (32 byte alignment) */
	output [31:0] to_mem_rd_req_addr,
	/** Acknowledgement from memory: ready to receive memory read request */
	input         from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input         from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input         from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready
);

//TODO: Please add your I-Cache code here

//声明与定义
	//FSM
	reg [7:0] current_state;
	reg [7:0] next_state;

	localparam WAIT 	= 8'b00000001;
	localparam TAG_RD	= 8'b00000010;
	localparam EVICT	= 8'b00000100;
	localparam MEM_RD	= 8'b00001000;
	localparam RECV		= 8'b00010000;
	localparam REFILL	= 8'b00100000;
	localparam RESP		= 8'b01000000;
	localparam CACHE_RD	= 8'b10000000;

	localparam is_WAIT 	= 0;
	localparam is_TAG_RD	= 1;
	localparam is_EVICT	= 2;
	localparam is_MEM_RD	= 3;
	localparam is_RECV	= 4;
	localparam is_REFILL	= 5;
	localparam is_RESP	= 6;
	localparam is_CACHE_RD	= 7;

	wire [23:0] tag;
	wire [ 2:0] index;
	wire [ 4:0] offset;

	reg  [`CACHE_SET- 1 : 0] valid_array [`CACHE_WAY - 1 : 0];
	wire [`TAG_LEN  - 1 : 0] tag_rdata   [`CACHE_WAY - 1 : 0];
	wire [`LINE_LEN - 1 : 0] data_rdata  [`CACHE_WAY - 1 : 0];
	wire [`LINE_LEN - 1 : 0] data_wdata;
	wire [`LINE_LEN - 1 : 0] data_selected;

	reg [7:0] LRU_cnt [`CACHE_WAY - 1:0][`CACHE_SET - 1:0];
	wire [1:0] way_LRU;

	wire [3:0] hit_way;
	wire ReadHit;
	wire ReadMiss;
	wire way_selected;

	reg [2:0] read_data_len;
	reg [31:0] read_data [7:0];

	wire [3:0] wen;



//时序逻辑
	//FSM
	always @ (posedge clk) begin
		if (rst) 
			current_state <= 8'b0;
		else 
			current_state <= next_state;
	end

	always @ (*) begin
		case (current_state)
			WAIT: begin
				if (from_cpu_inst_req_valid) begin
					next_state = TAG_RD;
				end
				else begin 
					next_state = WAIT;
				end
			end
			TAG_RD: begin
				if (ReadHit) begin
					next_state = CACHE_RD;
				end
				else begin
					next_state = EVICT;
				end
			end
			EVICT: begin
				next_state = MEM_RD;
			end
			MEM_RD: begin
				if (from_mem_rd_req_ready) begin
					next_state = RECV;
				end
				else begin
					next_state = MEM_RD;
				end
			end
			RECV: begin
				if (from_mem_rd_rsp_valid & from_mem_rd_rsp_last) begin
					next_state = REFILL;
				end
				else begin
					next_state = RECV;
				end
			end
			REFILL: begin
				next_state = RESP;
			end
			CACHE_RD: begin
				next_state = RESP;
			end
			RESP: begin
				if (from_cpu_cache_rsp_ready) begin
					next_state = WAIT;
				end
				else begin
					next_state = RESP;
				end
			end
			default: 
				next_state = WAIT;
		endcase
	end

	//valid_array
	integer i_valid;
	always @ (posedge clk) begin
		if (rst) begin
			for (i_valid = 0; i_valid < `CACHE_WAY; i_valid = i_valid + 1)
				valid_array[i_valid] <= 8'b0;
			end
		else if (current_state[is_EVICT]) begin
			valid_array[way_LRU][index] <= 1'b0;
		end
		else if (current_state[is_REFILL]) begin
			valid_array[way_LRU][index] <= 1'b1;
		end
	end


	//update LRU_cnt(用于替换算法)
	integer i_set;
	always @ (posedge clk) begin
		if (rst) begin
			for (i_set = 0; i_set < `CACHE_SET; i_set = i_set + 1) begin
				LRU_cnt[0][i_set] <= 8'b0;
				LRU_cnt[1][i_set] <= 8'b0;
				LRU_cnt[2][i_set] <= 8'b0;
				LRU_cnt[3][i_set] <= 8'b0;
			end
		end
		else if (current_state[is_RESP] && from_cpu_cache_rsp_ready)begin
			if (~hit_way[0]) 
				LRU_cnt[0][index] <= LRU_cnt[0][index] + 1;
			if (~hit_way[1]) 
				LRU_cnt[1][index] <= LRU_cnt[1][index] + 1;
			if (~hit_way[2]) 
				LRU_cnt[2][index] <= LRU_cnt[2][index] + 1;
			if (~hit_way[3]) 
				LRU_cnt[3][index] <= LRU_cnt[3][index] + 1;
		end
		else if (current_state[is_REFILL]) begin
			 LRU_cnt[way_LRU][index] <= 8'b0;
		end
	end

	//update read_data(从内存读数据)
	always @ (posedge clk) begin
		if(rst) begin
			read_data_len <=  2'b0;
		end
		else if (current_state[is_MEM_RD] && from_mem_rd_req_ready) begin
			read_data_len <= 2'b0;
		end
		else if (current_state[is_RECV] && from_mem_rd_rsp_valid) begin
			read_data_len <= read_data_len + 1'b1;
		end
	end

	always @ (posedge clk) begin
		if (current_state[is_RECV] && from_mem_rd_rsp_valid) begin
			read_data[read_data_len] <= from_mem_rd_rsp_data;
		end
	end



//组合逻辑
	//HandShake Signals
	assign to_cpu_inst_req_ready = current_state[is_WAIT];
	assign to_cpu_cache_rsp_valid = current_state[is_RESP];
	assign to_mem_rd_req_valid = current_state[is_MEM_RD];
	assign to_mem_rd_rsp_ready = current_state[is_RECV];

	//Input Decode
	assign {tag, index, offset} = from_cpu_inst_req_addr;
	assign to_mem_rd_req_addr = {from_cpu_inst_req_addr[31:5], 5'b0};

	//ReadHit or ReadMiss
	assign hit_way[0] = valid_array[0][index] & (tag_rdata[0] == tag);
	assign hit_way[1] = valid_array[1][index] & (tag_rdata[1] == tag);
	assign hit_way[2] = valid_array[2][index] & (tag_rdata[2] == tag);
	assign hit_way[3] = valid_array[3][index] & (tag_rdata[3] == tag);

	assign ReadHit = hit_way[0] | hit_way[1] | hit_way[2] | hit_way[3];
	assign ReadMiss = ~ReadHit;

	//select way
	assign way_selected = 	{(2){hit_way[0]}} & 2'b00 |
				{(2){hit_way[1]}} & 2'b01 |
				{(2){hit_way[2]}} & 2'b10 |
				{(2){hit_way[3]}} & 2'b11 ;

	//data to cpu
	assign data_selected =  {`LINE_LEN{hit_way[0]}} & data_rdata[0] |
				{`LINE_LEN{hit_way[1]}} & data_rdata[1] |
				{`LINE_LEN{hit_way[2]}} & data_rdata[2] |
				{`LINE_LEN{hit_way[3]}} & data_rdata[3];
	assign to_cpu_cache_rsp_data = data_selected >> {offset, 3'b0};

	//LRU(选择算法)
	assign way_LRU = (~valid_array[0][index])? 2'b00 :
			 (~valid_array[1][index])? 2'b01 :
			 (~valid_array[2][index])? 2'b10 :
			 (~valid_array[3][index])? 2'b11 :
			 (
			        (LRU_cnt[0][index] >= LRU_cnt[1][index])? 
				(LRU_cnt[0][index] >= LRU_cnt[2][index])?
				(LRU_cnt[0][index] >= LRU_cnt[3][index])? 2'b00 : 2'b11 :
				(LRU_cnt[2][index] >= LRU_cnt[3][index])? 2'b10 : 2'b11 :
				(LRU_cnt[1][index] >= LRU_cnt[2][index])?
				(LRU_cnt[1][index] >= LRU_cnt[3][index])? 2'b01 : 2'b11 :
				(LRU_cnt[2][index] >= LRU_cnt[3][index])? 2'b10 : 2'b11
			 );			


	//wen && data_wdata
	assign wen[0] = current_state[is_REFILL] & (way_LRU == 2'b00);
	assign wen[1] = current_state[is_REFILL] & (way_LRU == 2'b01);
	assign wen[2] = current_state[is_REFILL] & (way_LRU == 2'b10);
	assign wen[3] = current_state[is_REFILL] & (way_LRU == 2'b11);

	assign data_wdata = {read_data[7], read_data[6], read_data[5], read_data[4], read_data[3], read_data[2], read_data[1], read_data[0]};

	//例化
	tag_array tag_0 (
		.clk(clk),
		.waddr(index),
		.raddr(index),
		.wen(wen[0]),
		.wdata(tag),
		.rdata(tag_rdata[0])
    	);
	tag_array tag_1 (
		.clk(clk),
		.waddr(index),
		.raddr(index),
		.wen(wen[1]),
		.wdata(tag),
		.rdata(tag_rdata[1])
	);
	tag_array tag_2 (
		.clk(clk),
		.waddr(index),
		.raddr(index),
		.wen(wen[2]),
		.wdata(tag),
		.rdata(tag_rdata[2])
	);
	tag_array tag_3 (
		.clk(clk),
		.waddr(index),
		.raddr(index),
		.wen(wen[3]),
		.wdata(tag),
		.rdata(tag_rdata[3])
	);


	data_array data_0 (
		.clk(clk),
		.waddr(index),
		.raddr(index),
		.wen(wen[0]),
		.wdata(data_wdata),
		.rdata(data_rdata[0])
	);
	data_array data_1 (
		.clk(clk),
		.waddr(index),
		.raddr(index),
		.wen(wen[1]),
		.wdata(data_wdata),
		.rdata(data_rdata[1])
	);
	data_array data_2 (
		.clk(clk),
		.waddr(index),
		.raddr(index),
		.wen(wen[2]),
		.wdata(data_wdata),
		.rdata(data_rdata[2])
	);
	data_array data_3 (
		.clk(clk),
		.waddr(index),
		.raddr(index),
		.wen(wen[3]),
		.wdata(data_wdata),
		.rdata(data_rdata[3])
	);


endmodule
