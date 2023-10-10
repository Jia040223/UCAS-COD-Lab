`define Branch_or_Jump_BUS_WD  34
`define IF_TO_ID_BUS_WD  64

module IF_State(
        input                                    clk,
        input                                    rst,
        //block signals
        input                                    ID_Allow_in,
        //branch or jump signals
        input  [`Branch_or_Jump_BUS_WD - 1:0]    Branch_or_Jump_Bus,
        input                                    ID_Valid,
        //to id
        output                                   IF_to_ID_Valid,
        output [`IF_TO_ID_BUS_WD - 1:0]          IF_to_ID_Bus,
        //memory interface
        //Instruction request channel
        output reg [31:0]                        PC,
        output                                   Inst_Req_Valid,
        input                                    Inst_Req_Ready,
        //Instruction response channel
        input  [31:0]                            Instruction,
        input                                    Inst_Valid,
        output                                   Inst_Ready,
        //for BHV_SIM
        input                                    MemRead,
        input                                    Mem_Feedback
);
//声明与宏定义
        //HandShake Signal
        reg         IF_Valid;
        wire        IF_Ready;
        wire        IF_Allow_in;
        wire        to_IF_Valid;
        
        //PC
        wire [31:0] PC_abnormal;
        reg  [31:0] IF_PC;
        wire [31:0] IF_Instruction;
        
        //Branch or Jump
        wire        Branch_or_Jump; 
        reg         Branch_or_Jump_reg;
        reg         Branch_or_Jump_temp;
        wire        Branch_or_Jump_Valid;
        
        //FSM
        reg [4:0] current_state;
        reg [4:0] next_state;

        localparam INIT = 5'b00001;
        localparam IF =   5'b00010;
        localparam IW =   5'b00100;
        localparam TEMP = 5'b01000;
        localparam DONE = 5'b10000;

        //IR
        reg [31:0] IR;


//寄存器更新
        //FSM
        always @ (posedge clk) begin
		if (rst)
			current_state <= INIT;
		else
			current_state <= next_state;
	end


	/* FSM 2 */
	always @ (*) begin
		case (current_state)
                        INIT:
                                next_state = IF;
                        IF:
                                if (Inst_Req_Ready & Inst_Req_Valid) //握手成功
                                        next_state = IW;
                                else
                                        next_state = IF;
                        IW:
                                if (Inst_Valid) begin
                                        if (ID_Valid && Branch_or_Jump || Branch_or_Jump_reg)
                                                /* Branch will happen */
                                                next_state = TEMP;
                                        else
                                                next_state = DONE;
                                end
                                else begin
                                        next_state = IW;
                                end
                        TEMP:
                                if(Branch_or_Jump_Valid) begin
                                        next_state = IF;
                                end
                                else    
                                        next_state = TEMP;
                        DONE:	begin	
                                        if(ID_Allow_in) begin
                                                next_state = IF;        
                                        end
                                        else begin
                                                next_state = DONE;
                                        end
                                end
                        default:        next_state = INIT;
		endcase
	end


        //PC更新
        always @ (posedge clk) begin
		if (rst)
			PC <= 32'd0;
		else if (current_state == IW
			&& (ID_Valid && Branch_or_Jump || Branch_or_Jump_reg))
			        PC <= PC_abnormal;
                else if(current_state == TEMP & Branch_or_Jump_Valid)
                                PC <= PC_abnormal;
		else if (current_state == DONE) begin
			if (ID_Valid && Branch_or_Jump || Branch_or_Jump_reg)
				PC <= PC_abnormal;  /* Branch */
			else if (next_state == IF) begin
				PC <= PC + 32'd4;
                        end
		end
	end


        //IR
        always @ (posedge clk) begin
		if (current_state == IW && Inst_Valid)
			IR <= Instruction;
	end


        //Branch_or_Jump_reg
	always @ (posedge clk) begin
		if (rst) begin		
			Branch_or_Jump_reg <= 0;
                end
		else if (ID_Valid && Branch_or_Jump) begin
			Branch_or_Jump_reg <= 1;
                end
		else if (((current_state == IW) & Inst_Valid
			| current_state == DONE) && Branch_or_Jump_reg) begin 
			        Branch_or_Jump_reg <= 0;
                        end
	end


        //IF_PC
        always @(posedge clk) begin
                if(rst) begin
                        IF_PC <= 32'hfffffffc;
                end
                else if(Inst_Req_Valid & Inst_Req_Ready) begin
                        IF_PC <= PC;
                end
        end

        
        //IF_Valid
        always @(posedge clk) begin
                if(rst) begin
                        IF_Valid <= 1'b0;
                end
                else if(IF_Allow_in) begin
                        IF_Valid <= to_IF_Valid & Inst_Req_Ready;
                end
        end
        


//其它组合逻辑
        //Branch or Jump
        assign {Branch_or_Jump_Valid, Branch_or_Jump, PC_abnormal}   = Branch_or_Jump_Bus;

        //传给IF的信号是否有效
        assign to_IF_Valid                     = ~rst;

        //访存信号
        assign Inst_Req_Valid = (current_state == IF) & ~MemRead; //行为仿真需要错开
	assign Inst_Ready = (current_state == IW || current_state == INIT);

        //HandShake Signals (IF <-> ID)
        assign IF_Ready    = (current_state == DONE); //访存请求成功且访存成功
        assign IF_Allow_in     = !IF_Valid || IF_Ready && ID_Allow_in;  //IF和ID握手成功
        assign IF_to_ID_Valid = IF_Valid & IF_Ready; //非跳转分支指令且IF工作正常
        
        //DataPath (IF --> ID)
        assign IF_Instruction = IR;
        assign IF_to_ID_Bus = {IF_Instruction, PC};


endmodule


