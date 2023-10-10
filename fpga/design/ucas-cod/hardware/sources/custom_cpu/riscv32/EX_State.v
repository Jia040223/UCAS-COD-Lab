`define ID_TO_EX_BUS_WD  165
`define EX_TO_MEM_BUS_WD 108
`define RDW_BUS_WD       39

module EX_State(
        input                                   clk,
        input                                   rst,
        //Allow_in
        input                                   MEM_Allow_in,
        output                                  EX_Allow_in,
        //from id
        input                                   ID_to_EX_Valid,
        input  [`ID_TO_EX_BUS_WD - 1 :0]        ID_to_EX_Bus,
        //to MEM
        output                                  EX_to_MEM_Valid,
        output [`EX_TO_MEM_BUS_WD - 1:0]        EX_to_MEM_Bus,
        //MEM
        output [31                   :0]        Address,
        output                                  MEMWrite,
        output [31                   :0]        Write_data,
        output [3                    :0]        Write_strb,
        output                                  MEMRead,
        input                                   MEM_Req_Ready,
        //rdw to id
        output [`RDW_BUS_WD - 1      :0]        rdw_EX_Bus,
        input                                   Mem_Feedback
);

//声明  
        //EX内信号
        reg  [`ID_TO_EX_BUS_WD - 1:0] ID_to_EX_Bus_reg;
        reg  EX_Valid;
        wire EX_Ready;

         //data from ID
        wire [31:0]     PC; 
        wire           WB_wen;
        wire           MEM_wen;

        wire [4:0]      rs;
        wire [4:0]      rt;
        wire [31:0]     RF_rdata1;
        wire [31:0]     RF_rdata2;
        wire [4:0]      RF_waddr; 

        wire [31:0]     imm;
        wire [2:0]      funct3;

        wire            ALUEn;
        wire            ShiftEn;
        wire            MULEn;

        wire            AUIPC;
        wire            LUI;

        wire            LOAD;
        wire            STORE;

        wire            ALUSrc;
        wire            ShiftSrc;

        wire            Branch;
        wire            JALR;
        wire            J_Type; 

        //ALU and Result
	wire [31:0]     ALU_A;
	wire [31:0]	ALU_B;
	wire [2:0]	ALUop;
	wire [1:0]	Shiftop;
	wire [31:0]	ALUResult,ShifterResult;
	wire [31:0]	MULResult;
	wire 		Overflow,CarryOut,Zero;
        wire [31:0]	Calc_Result;
	wire [31:0]	Result;

        //Mem_req Handshake Signals
        reg MEM_req_succ;
        

//时序逻辑
        //EX_Valid
        always @(posedge clk) begin
                if(rst) begin
                        EX_Valid <= 1'b0;
                end
                else if(EX_Allow_in) begin
                        EX_Valid <= ID_to_EX_Valid;
                end
        end


        //ID_to_EX_Bus_reg
        always @(posedge clk) begin
                if(ID_to_EX_Valid & EX_Allow_in) begin
                        ID_to_EX_Bus_reg <= ID_to_EX_Bus;
                end
        end


        //MEM_req_succ(访存请求握手成功)
        always @(posedge clk) begin
                if(~MEM_req_succ | EX_Allow_in) begin //握手未成功时需要一直判断
                        MEM_req_succ <= MEM_Req_Ready & (MEMRead | MEMWrite);
                end
        end



//组合逻辑
        //DataPath (ID --> EX)
        assign { rs,            //164:160
                rt,             //159:155
                RF_waddr,       //154:150
                RF_rdata1,      //149:118
                RF_rdata2,      //117:86
                ALUop,          //85:83
                Shiftop,        //82:81
                ALUSrc,         //80:80
                ShiftSrc,       //79:79
                ALUEn,          //78:78
                ShiftEn,        //77:77
                MULEn,          //76:76
                AUIPC,          //75:75
                LUI,            //74:74
                LOAD,           //73:73
                STORE,          //72:72
                Branch,         //71:71
                funct3,         //70:68
                JALR,           //67:67 
                J_Type,         //66:66 
                MEM_wen,        //65:65
                WB_wen,         //64:64
                imm,            //63:32
                PC              //31:0
                } = ID_to_EX_Bus_reg;


        //ALU and Result
        assign ALU_A = AUIPC ? PC :RF_rdata1; //AUIPC指令的操作数之一为PC
	assign ALU_B = ALUSrc ? imm :RF_rdata2;


        //ALU
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
		.A		(RF_rdata1),
		.B		(ShiftSrc ? imm[4:0] : RF_rdata2[4:0]), //移位对32取模
		.Shiftop	(Shiftop),
		.Result		(ShifterResult)
	);


        //MULTIPLY
	assign MULResult = RF_rdata1 * RF_rdata2;


        //Choose Result
        assign Calc_Result = {(32){ALUEn}}  &  ALUResult | 
		             {(32){ShiftEn}} &  ShifterResult | 
			     {(32){MULEn}}   &  MULResult; //Choose Result


        //传给MEM的Result
        assign Result 		=  LUI ? imm :
                                   (J_Type | JALR) ? (PC + 4) :
                                   Calc_Result;

        
        //DataPath (EX --> ID)
        assign rdw_EX_Bus  = {  ~LOAD,                  //38:38
                                WB_wen & EX_Valid,      //37:37
                                RF_waddr,               //36:32
                                Result                  //31:0
                                };
        

        //DataPath (EX --> MEM)
        assign EX_to_MEM_Bus = {RF_rdata2,      //107:76
                                Result,         //75:44
                                funct3,         //43:41
                                LOAD,           //40:40
                                STORE,          //39:39
                                MEM_wen,        //38:38
                                WB_wen,         //37:37
                                RF_waddr,       //36:32
                                PC              //31:0
                                };
        
        
        //HandShake Signals between MEM and EX
        assign EX_Ready     = (MEM_req_succ | ~LOAD & ~STORE);  //访存请求成功或者不是访存指令
        assign EX_Allow_in      = (!EX_Valid || EX_Ready && MEM_Allow_in) & Mem_Feedback; //EX和MEM握手成功
        assign EX_to_MEM_Valid = EX_Valid & EX_Ready; //EX阶段工作正常

        
        //Write
	assign Address 		= Result & ~32'b11; //对齐
	assign Write_data	= RF_rdata2 << {Result[1:0], 3'b0};
	assign Write_strb	= {( Result[1] | funct3[1]) & ( Result[0] | funct3[0] | funct3[1]),
				   ( Result[1] | funct3[1]) & (~Result[0] | funct3[0] | funct3[1]),
				   (~Result[1] | funct3[1]) & ( Result[0] | funct3[0] | funct3[1]),
				   (~Result[1] | funct3[1]) & (~Result[0] | funct3[0] | funct3[1])};


        //Memory Request HandShake Signals
        assign MEMRead    = LOAD & EX_Valid & ~MEM_req_succ;  //LOAD指令，且访存请求未成功，EX阶段有效
        assign MEMWrite   = STORE & EX_Valid & ~MEM_req_succ; //STORE指令，且访存请求未成功，EX阶段有效
    
    
endmodule


