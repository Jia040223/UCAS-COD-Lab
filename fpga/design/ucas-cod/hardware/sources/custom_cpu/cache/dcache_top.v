`timescale 10ns / 1ns

`define CACHE_SET	8
`define CACHE_WAY	4
`define TAG_LEN		24
`define LINE_LEN	256

module dcache_top (
	input	      clk,
	input	      rst,
  
	//CPU interface
	/** CPU memory/IO access request to Cache: valid signal */
	input         from_cpu_mem_req_valid,
	/** CPU memory/IO access request to Cache: 0 for read; 1 for write (when req_valid is high) */
	input         from_cpu_mem_req,
	/** CPU memory/IO access request to Cache: address (4 byte alignment) */
	input  [31:0] from_cpu_mem_req_addr,
	/** CPU memory/IO access request to Cache: 32-bit write data */
	input  [31:0] from_cpu_mem_req_wdata,
	/** CPU memory/IO access request to Cache: 4-bit write strobe */
	input  [ 3:0] from_cpu_mem_req_wstrb,
	/** Acknowledgement from Cache: ready to receive CPU memory access request */
	output        to_cpu_mem_req_ready,
		
	/** Cache responses to CPU: valid signal */
	output        to_cpu_cache_rsp_valid,
	/** Cache responses to CPU: 32-bit read data */
	output [31:0] to_cpu_cache_rsp_data,
	/** Acknowledgement from CPU: Ready to receive read data */
	input         from_cpu_cache_rsp_ready,
		
	//Memory/IO read interface
	/** Cache sending memory/IO read request: valid signal */
	output        to_mem_rd_req_valid,
	/** Cache sending memory read request: address
	  * 4 byte alignment for I/O read 
	  * 32 byte alignment for cache read miss */
	output [31:0] to_mem_rd_req_addr,
        /** Cache sending memory read request: burst length
	  * 0 for I/O read (read only one data beat)
	  * 7 for cache read miss (read eight data beats) */
	output [ 7:0] to_mem_rd_req_len,
        /** Acknowledgement from memory: ready to receive memory read request */
	input	      from_mem_rd_req_ready,

	/** Memory return read data: valid signal of one data beat */
	input	      from_mem_rd_rsp_valid,
	/** Memory return read data: 32-bit one data beat */
	input  [31:0] from_mem_rd_rsp_data,
	/** Memory return read data: if current data beat is the last in this burst data transmission */
	input	      from_mem_rd_rsp_last,
	/** Acknowledgement from cache: ready to receive current data beat */
	output        to_mem_rd_rsp_ready,

	//Memory/IO write interface
	/** Cache sending memory/IO write request: valid signal */
	output        to_mem_wr_req_valid,
	/** Cache sending memory write request: address
	  * 4 byte alignment for I/O write 
	  * 4 byte alignment for cache write miss
          * 32 byte alignment for cache write-back */
	output [31:0] to_mem_wr_req_addr,
        /** Cache sending memory write request: burst length
          * 0 for I/O write (write only one data beat)
          * 0 for cache write miss (write only one data beat)
          * 7 for cache write-back (write eight data beats) */
	output [ 7:0] to_mem_wr_req_len,
        /** Acknowledgement from memory: ready to receive memory write request */
	input         from_mem_wr_req_ready,

	/** Cache sending memory/IO write data: valid signal for current data beat */
	output        to_mem_wr_data_valid,
	/** Cache sending memory/IO write data: current data beat */
	output [31:0] to_mem_wr_data,
	/** Cache sending memory/IO write data: write strobe
	  * 4'b1111 for cache write-back 
	  * other values for I/O write and cache write miss according to the original CPU request*/ 
	output [ 3:0] to_mem_wr_data_strb,
	/** Cache sending memory/IO write data: if current data beat is the last in this burst data transmission */
	output        to_mem_wr_data_last,
	/** Acknowledgement from memory/IO: ready to receive current data beat */
	input	      from_mem_wr_data_ready
);

  //TODO: Please add your D-Cache code here

//声明与宏定义
        //FSM
        localparam WAIT   = 10'b0000000001;
        localparam TAG_RD = 10'b0000000010;
        localparam CACHE  = 10'b0000000100;
        localparam RESP   = 10'b0000001000;
        localparam EVICT  = 10'b0000010000;
        localparam MEM_RD = 10'b0000100000;
        localparam RECV   = 10'b0001000000;
        localparam REFILL = 10'b0010000000;
        localparam MEM_WT = 10'b0100000000;
        localparam SEND   = 10'b1000000000;

        localparam is_WAIT   = 0;
        localparam is_TAG_RD = 1;
        localparam is_CACHE  = 2; 
        localparam is_RESP   = 3;
        localparam is_EVICT  = 4;
        localparam is_MEM_RD = 5;
        localparam is_RECV   = 6;
        localparam is_REFILL = 7;
        localparam is_MEM_WT = 8;
        localparam is_SEND   = 9;

        reg [9:0] current_state;
        reg [9:0] next_state;

        //reg for cpu_mem_req
        reg [31:0] reg_from_cpu_mem_req_addr;
        reg [31:0] reg_from_cpu_mem_req_wdata;
        reg [4:0] reg_from_cpu_mem_req_wstrb;
        reg reg_from_cpu_mem_req;

        // decode
        wire [23:0] tag;
        wire [2:0] index;
        wire [4:0] offset;

        // bypass
        wire bypass;

        // hit?
        wire hit;
        wire [3:0] hit_way;  // one-hot
        wire [1:0] hit_way_num;

        reg [7:0] LRU_cnt [`CACHE_WAY - 1:0][`CACHE_SET - 1:0];
        wire [1:0] way_LRU;

        // dirty?
        wire dirty;

        reg [31:0] rd_buffer[7:0];
        // burst counter
        reg [7:0] burst_num;

        wire cache_write;
        wire [3:0] data_wen;
        wire [255:0] data_wdata, data_rdata[3:0], write_mask;

        wire [255:0] cache_data;
        wire [255:0] evict_data;

        wire [3:0] evict_way;

        reg [7:0] valid_array[3:0];
        reg [7:0] dirty_array[3:0];

        wire [23:0] tag_rdata[3:0];
        wire [23:0] evict_tag;

//时序逻辑
        // current_state
        always @(posedge clk) begin
            if (rst) 
                current_state <= WAIT;
            else
                current_state <= next_state;
        end

        // next_state
        always @(*) begin
            case (current_state)
                WAIT: begin
                    if (from_cpu_mem_req_valid) begin
                        if (|from_cpu_mem_req_addr[31:30] | ~|from_cpu_mem_req_addr[31:5]) begin  // 0x40000000~0xFFFFFFFF | 0x00~0x1F -> bypass(旁路)
                            if (from_cpu_mem_req) begin  //MemWrite 
                                next_state = MEM_WT;
                            end
                            else begin                   //MemRead 
                                next_state = MEM_RD;
                            end
                        end
                        else begin                      
                            next_state = TAG_RD;     //not bypass
                        end
                    end
                    else begin                          
                        next_state = WAIT;
                    end
                end
                TAG_RD: begin
                    if (hit) begin                   //Hit Cache
                        next_state = CACHE;
                    end
                    else begin
                        next_state = EVICT;
                    end
                end
                CACHE: begin
                    if (reg_from_cpu_mem_req)  //MeMWrite -> don't need resp
                        next_state = WAIT;
                    else                     // MemRead -> need resp
                        next_state = RESP;
                end
                RESP: begin
                    if (from_cpu_cache_rsp_ready) //握手成功
                        next_state = WAIT;
                    else
                        next_state = RESP;
                end
                EVICT: begin
                    if (dirty)                  //dirty -> need Write
                        next_state = MEM_WT;
                    else
                        next_state = MEM_RD;
                end
                MEM_RD: begin
                    if (from_mem_rd_req_ready) //内存请求握手成功
                        next_state = RECV;
                    else
                        next_state = MEM_RD;
                end
                RECV: begin
                    if (from_mem_rd_rsp_valid & from_mem_rd_rsp_last) begin
                        if (bypass)             //bypass -> don't need refill Cache
                            next_state = RESP;
                        else
                            next_state = REFILL;
                    end
                    else
                        next_state = RECV;
                end
                REFILL: begin
                    if (reg_from_cpu_mem_req)  // MemWrite -> need to write Cache
                        next_state = CACHE;
                    else                       // MemRead -> don't need to write Cache
                        next_state = RESP;
                end
                MEM_WT: begin
                    if (from_mem_wr_req_ready) //内存请求握手成功
                        next_state = SEND;
                    else
                        next_state = MEM_WT;
                end
                SEND: begin
                    if (from_mem_wr_data_ready & to_mem_wr_data_last) begin
                        if (bypass)                 //bypass -> end
                            next_state = WAIT;
                        else                        //not bypass -> continue to write Cache
                            next_state = MEM_RD;    
                    end
                    else
                        next_state = SEND;
                end
                default: begin
                    next_state = WAIT;
                end
            endcase
        end


        //register for cpu_mem_req
        always @(posedge clk) begin
            if (current_state[is_WAIT] & from_cpu_mem_req_valid) begin
                reg_from_cpu_mem_req_addr  <= from_cpu_mem_req_addr;
            end
        end

        always @(posedge clk) begin
            if (current_state[is_WAIT] & from_cpu_mem_req_valid) begin
                reg_from_cpu_mem_req_wdata <= from_cpu_mem_req_wdata;
            end
        end

        always @(posedge clk) begin
            if (current_state[is_WAIT] & from_cpu_mem_req_valid) begin
                reg_from_cpu_mem_req_wstrb <= from_cpu_mem_req_wstrb;
            end
        end

        always @(posedge clk) begin
            if (current_state[is_WAIT] & from_cpu_mem_req_valid) begin
                reg_from_cpu_mem_req       <= from_cpu_mem_req;
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
            else if (current_state[is_CACHE])begin
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


        //rd_buffer
        always @(posedge clk) begin
            if (to_mem_rd_rsp_ready & from_mem_rd_rsp_valid) begin
                rd_buffer[burst_num] <= from_mem_rd_rsp_data;
            end
        end

        //burst_num
        always @(posedge clk) begin
            if(rst) begin
                burst_num <= 8'b0;
            end
            else if (current_state[is_MEM_RD] | current_state[is_MEM_WT]) begin   // reset or MEM_RD or MEM_WT
                burst_num <= 8'b0;
            end
            else if ((to_mem_rd_rsp_ready & from_mem_rd_rsp_valid) | (from_mem_wr_data_ready & to_mem_wr_data_valid)) begin
                burst_num <= burst_num + 1;
            end
        end

        //valid array
        always @(posedge clk) begin
            if (rst) begin
                valid_array[0] <= 8'b0;
                valid_array[1] <= 8'b0;
                valid_array[2] <= 8'b0;
                valid_array[3] <= 8'b0;
            end
            else if (current_state[is_EVICT]) begin  // EVICT
                valid_array[way_LRU][index] <= 0;
            end
            else if (current_state[is_REFILL]) begin  // REFILL
                valid_array[way_LRU][index] <= 1;
            end
        end


        //dirty array
        always @(posedge clk) begin
            if (rst) begin
                dirty_array[0] <= 8'b0;
                dirty_array[1] <= 8'b0;
                dirty_array[2] <= 8'b0;
                dirty_array[3] <= 8'b0;
            end
            else if (current_state[is_CACHE] & reg_from_cpu_mem_req) begin  // CACHE & write
                dirty_array[hit_way_num][index] <= 1;
            end
            else if (current_state[is_REFILL]) begin                       // REFILL
                dirty_array[way_LRU][index] <= 0;
            end
        end


//组合逻辑
        //HandShake Signals
        assign to_cpu_mem_req_ready = current_state[is_WAIT]; 
        assign to_cpu_cache_rsp_valid = current_state[is_RESP];

        assign to_mem_rd_req_valid = current_state[is_MEM_RD];
        assign to_mem_rd_rsp_ready = current_state[is_RECV];

        assign to_mem_wr_req_valid = current_state[is_MEM_WT];
        assign to_mem_wr_data_valid = current_state[is_SEND];

        // decode
        assign {tag, index, offset} = reg_from_cpu_mem_req_addr;

        //bypass
        assign bypass = |reg_from_cpu_mem_req_addr[31:30] | ~|reg_from_cpu_mem_req_addr[31:5];  // 0x40000000~0xFFFFFFFF | 0x00~0x1F --> bypass

        //Hit
        assign hit_way[0] = valid_array[0][index] & (tag_rdata[0] == tag);
        assign hit_way[1] = valid_array[1][index] & (tag_rdata[1] == tag);
        assign hit_way[2] = valid_array[2][index] & (tag_rdata[2] == tag);
        assign hit_way[3] = valid_array[3][index] & (tag_rdata[3] == tag);

        assign hit = |hit_way;
        assign hit_way_num = {hit_way[3] | hit_way[2], 
                              hit_way[3] | hit_way[1]};


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
        
        assign evict_way = {    &way_LRU,                       //evict_way ---独热码
                                way_LRU[1] & ~way_LRU[0],
                                ~way_LRU[1] & way_LRU[0],
                                ~|way_LRU   };
        
        // dirty
        assign dirty = dirty_array[way_LRU][index];

        // rsp_data
        assign to_cpu_cache_rsp_data = bypass ? rd_buffer[0]
                                      : cache_data >> {offset, 3'b0};

        //Mem_Read request addr & len
        assign to_mem_rd_req_addr = bypass ? {reg_from_cpu_mem_req_addr[31:2], 2'b0}
                                    : {reg_from_cpu_mem_req_addr[31:5], 5'b0};
        assign to_mem_rd_req_len = bypass ? 8'b0 : 8'b111;

        //Mem_Write request addr & len
        assign to_mem_wr_req_addr = bypass ? {reg_from_cpu_mem_req_addr[31:2], 2'b0}
                                    : {evict_tag, index, 5'b0};
        assign to_mem_wr_req_len = bypass ? 8'b0 : 8'b111;

        // Mem_Write
        assign to_mem_wr_data_strb = bypass ? reg_from_cpu_mem_req_wstrb : 4'b1111;

        assign to_mem_wr_data = bypass ? reg_from_cpu_mem_req_wdata
                                : evict_data >> {burst_num, 5'b0};

        assign to_mem_wr_data_last = (burst_num == to_mem_rd_req_len);


        //  data array
        assign cache_write = current_state[is_CACHE] & reg_from_cpu_mem_req; //Write Cache Signal
        assign write_mask = {{8{reg_from_cpu_mem_req_wstrb[3]}}, 
                             {8{reg_from_cpu_mem_req_wstrb[2]}}, 
                             {8{reg_from_cpu_mem_req_wstrb[1]}}, 
                             {8{reg_from_cpu_mem_req_wstrb[0]}}} << {offset, 3'b000}; //Mask --字节掩码

        assign data_wdata = cache_write ? (((reg_from_cpu_mem_req_wdata) << {offset, 3'b000}) & write_mask) | (cache_data & ~write_mask)         // write not miss
                            : {rd_buffer[7], rd_buffer[6], rd_buffer[5], rd_buffer[4], rd_buffer[3], rd_buffer[2], rd_buffer[1], rd_buffer[0]};  // read / write Miss -> Read_data from Mem

        assign data_wen = {4{current_state[is_REFILL]}} & evict_way |  //REFILL on  read / write miss  
                          {4{cache_write}} & hit_way;  //  write not miss; 

        assign cache_data =  hit_way[0] ? data_rdata[0]
                           : hit_way[1] ? data_rdata[1]
                           : hit_way[2] ? data_rdata[2]
                           : data_rdata[3];

        assign evict_data =   evict_way[0] ? data_rdata[0]
                            : evict_way[1] ? data_rdata[1]
                            : evict_way[2] ? data_rdata[2]
                            : data_rdata[3];

        //例化
        data_array data_way_0 (
            .clk(clk),
            .waddr(index),
            .raddr(index),
            .wen(data_wen[0]),
            .wdata(data_wdata),
            .rdata(data_rdata[0])
        );
        data_array data_way_1 (
            .clk(clk),
            .waddr(index),
            .raddr(index),
            .wen(data_wen[1]),
            .wdata(data_wdata),
            .rdata(data_rdata[1])
        );
        data_array data_way_2 (
            .clk(clk),
            .waddr(index),
            .raddr(index),
            .wen(data_wen[2]),
            .wdata(data_wdata),
            .rdata(data_rdata[2])
        );
        data_array data_way_3 (
            .clk(clk),
            .waddr(index),
            .raddr(index),
            .wen(data_wen[3]),
            .wdata(data_wdata),
            .rdata(data_rdata[3])
        );


        // tag array
        assign evict_tag =   evict_way[0] ? tag_rdata[0]
                           : evict_way[1] ? tag_rdata[1]
                           : evict_way[2] ? tag_rdata[2]
                           : tag_rdata[3];

        //例化
        tag_array tag_way_0 (
            .clk(clk),
            .waddr(index),
            .raddr(index),
            .wen(data_wen[0]),
            .wdata(tag),
            .rdata(tag_rdata[0])
        );
        tag_array tag_way_1 (
            .clk(clk),
            .waddr(index),
            .raddr(index),
            .wen(data_wen[1]),
            .wdata(tag),
            .rdata(tag_rdata[1])
        );
        tag_array tag_way_2 (
            .clk(clk),
            .waddr(index),
            .raddr(index),
            .wen(data_wen[2]),
            .wdata(tag),
            .rdata(tag_rdata[2])
        );
        tag_array tag_way_3 (
            .clk(clk),
            .waddr(index),
            .raddr(index),
            .wen(data_wen[3]),
            .wdata(tag),
            .rdata(tag_rdata[3])
        );


endmodule
