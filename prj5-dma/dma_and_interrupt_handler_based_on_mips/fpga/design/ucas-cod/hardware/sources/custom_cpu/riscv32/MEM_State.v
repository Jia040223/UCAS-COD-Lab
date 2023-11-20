`define EX_TO_MEM_BUS_WD 108
`define MEM_TO_WB_BUS_WD 70
`define RDW_BUS_WD       39

module MEM_State(
        input                            clk,
        input                            rst,
        //Allow_in
        input                            WB_Allow_in,
        output                           MEM_Allow_in,
        //from EX
        input                            EX_to_MEM_Valid,
        input  [`EX_TO_MEM_BUS_WD - 1:0] EX_to_MEM_Bus,
        //to WB
        output                           MEM_to_WB_Valid,
        output [`MEM_TO_WB_BUS_WD - 1:0] MEM_to_WB_Bus,
        //MEM
        input  [31                   :0] Read_data,
        input                            Read_data_Valid,
        output                           Read_data_Ready, 

        //rdw to id/EX
        output [`RDW_BUS_WD - 1:0] rdw_MEM_Bus
);
//声明
        //HandShake Signal
        reg  MEM_Valid;
        wire MEM_Ready;
        reg  [`EX_TO_MEM_BUS_WD - 1:0] EX_to_MEM_Bus_reg;

        //Other Signals from EX
        wire [31:0]     RF_rdata2;
        wire [2:0]      funct3;
        wire [31:0]     Result;
        wire            LOAD;
        wire            STORE;
        wire            MEM_wen;
        wire            WB_wen;
        wire [4:0]      RF_waddr;
        wire [31:0]     PC;
        
        //Read Data from Memory
        wire [31:0]	Read_data_shifted;
	wire [31:0]	Read_data_masked;
	wire 		Read_data_sign_bit;

        //final Write Back Data
        wire [31:0]     final_result;
        


//时序逻辑
        //MEM_Valid
        always @(posedge clk) begin
                if(rst) begin
                        MEM_Valid <= 1'b0;
                end
                else if(MEM_Allow_in) begin
                        MEM_Valid <= EX_to_MEM_Valid;
                end
        end


        //EX_to_MEM_Bus_reg
        always @(posedge clk) begin
                if(EX_to_MEM_Valid & MEM_Allow_in) begin
                        EX_to_MEM_Bus_reg <= EX_to_MEM_Bus;
                end
        end



//组合逻辑
        //DataPath (EX --> MEM)
        assign {RF_rdata2,      //107:76
                Result,         //75:44
                funct3,         //43:41
                LOAD,           //40:40
                STORE,          //39:39
                MEM_wen,        //38:38
                WB_wen,         //37:37
                RF_waddr,       //36:32
                PC              //31:0
                } = EX_to_MEM_Bus_reg;
        

        //Read Data From Memory
	assign Read_data_shifted 	= Read_data >> {Result[1:0], 3'b0};
	assign Read_data_sign_bit 	= Read_data_shifted[funct3[1:0]==2'b01 ? 15 : 7];//符号位

	assign Read_data_masked 	= Read_data_shifted & {{(16){funct3[1]}}, {(8){funct3[0] | funct3[1]}}, {(8){1'b1}}} |
				         {(32){~funct3[2] & Read_data_sign_bit}} & ~{{(16){funct3[1]}}, {(8){funct3[0] | funct3[1]}}, {(8){1'b1}}}; 
					//字节掩码进行数据选择并进行符号位或者零扩展


        //最终写回的数据
        assign final_result             = LOAD ? Read_data_masked : Result;


        //DataPath (MEM --> ID)
        assign rdw_MEM_Bus =  { MEM_Ready,              //38:38
                                WB_wen & MEM_Valid,     //37:37
                                RF_waddr,               //36:32
                                final_result            //31:0
                                };
        

        //HandShake Signals
        assign MEM_Ready        =  ~LOAD | Read_data_Valid; //非LOAD指令或访存成功
        assign MEM_Allow_in     =  !MEM_Valid || MEM_Ready && WB_Allow_in; //MEM和WB握手成功
        assign MEM_to_WB_Valid  =  MEM_Valid & MEM_Ready; //MEM工作正常

        assign Read_data_Ready  =  LOAD & MEM_Valid & WB_Allow_in | rst;
        
        
        //DataPath (MEM --> WB)
        assign MEM_to_WB_Bus = {WB_wen,         //69:69
                                RF_waddr,       //68:64
                                final_result,   //63:32
                                PC              //31:0
                                };


endmodule


