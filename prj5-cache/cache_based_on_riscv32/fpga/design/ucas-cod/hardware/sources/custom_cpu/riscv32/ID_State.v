`define IF_TO_ID_BUS_WD  64
`define ID_TO_EX_BUS_WD  165
`define WB_TO_RF_BUS_WD  38
`define RDW_BUS_WD       39
`define Branch_or_Jump_BUS_WD  34

module ID_State(
        input                                   clk,
        input                                   rst,
        //allowin
        input                                   EX_Allow_in,
        output                                  ID_Allow_in,
        //from IF
        input                                   IF_to_ID_Valid,
        input  [`IF_TO_ID_BUS_WD - 1:0]         IF_to_ID_Bus,
        //to EX
        output                                  ID_to_EX_Valid,
        output [`ID_TO_EX_BUS_WD - 1:0]         ID_to_EX_Bus,
        //to RegFile: from WB
        input  [`WB_TO_RF_BUS_WD - 1:0]         WB_to_RegFile_Bus,
        //RDW signals: form EX, MEM, WB
        input  [`RDW_BUS_WD - 1:0]              rdw_EX_Bus,
        input  [`RDW_BUS_WD - 1:0]              rdw_MEM_Bus,
        input  [`RDW_BUS_WD - 1:0]              rdw_WB_Bus,
         //to if
        output                                  to_IF_Valid,
        output [`Branch_or_Jump_BUS_WD - 1:0]   Branch_or_Jump_Bus,
        input                                   Mem_Feedback
);

//声明
        //ID内信号
        reg  ID_Valid;
        wire ID_Ready;
        
        reg[`IF_TO_ID_BUS_WD - 1:0] IF_to_ID_Bus_reg;

        //Instruction
        wire [31:0] Instruction;

        //PC
        wire [31:0] PC;
       
        //Reg_File
        wire [4 :0] RF_raddr1;
        wire [4 :0] RF_raddr2;
        wire [31:0] RF_rdata1;
        wire [31:0] RF_rdata2;
        wire        RF_wen;
        wire [4 :0] RF_waddr;
        wire [31:0] RF_wdata;
        
        //RDW signals: form EX, MEM, WB
        wire        rdw_EX_addr_valid;
        wire        rdw_EX_data_valid;
        wire [4 :0] rdw_EX_addr;
        wire [31:0] rdw_EX_data;
        wire        rdw_MEM_addr_valid;
        wire        rdw_MEM_data_valid;
        wire [4 :0] rdw_MEM_addr;
        wire [31:0] rdw_MEM_data;
        wire        rdw_WB_addr_valid;
        wire        rdw_WB_data_valid;
        wire [4 :0] rdw_WB_addr;
        wire [31:0] rdw_WB_data;
       
        wire        rs_from_EX;
        wire        rs_from_MEM;
        wire        rs_from_WB;
        wire        rs_from_RegFile;

        wire        rt_from_EX;
        wire        rt_from_MEM;
        wire        rt_from_WB;
        wire        rt_from_RegFile;
        

        //Instruction Decode
	wire [6:0]  funct7;
	wire [4:0]  rs;
	wire [4:0]  rt;
	wire [2:0]  funct3;
	wire [4:0]  rd;
	wire [6:0]  opcode;
	wire [31:0] imm;

        //Instruction Type
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

        wire MEM_wen;
        wire WB_wen;

        wire [4:0] dest;

        //Control Signal 
	wire Branch,MemtoReg,ALUEn,ShiftEn,MULEn,ALUSrc,ShiftSrc;

        //CLA (for Branch and Jump)
        wire [31:0]     CLA_A;
	wire [31:0]	CLA_B;
        wire            CLA_ZF;
        wire            CLA_OF;
        wire            CLA_CF;
        wire            CLA_SF;
        wire [31:0]     CLA_result;

        //ALU & Shifter Data
	wire [2:0]	ALUop;
	wire [1:0]	Shiftop;

        //RF_Final_data
        wire [31:0]     RF_Final_data1;
        wire [31:0]     RF_Final_data2;

        //Branch and Jump
        wire [31:0]     Branch_Address;
        wire [31:0]     Jump_Address;

        wire            Jump;

        wire            Branch_or_Jump_wen;
        wire [31:0]     Branch_or_Jump_PC;
        wire            Branch_or_Jump_Valid;
        


//时序逻辑
        //ID_Valid
        always @(posedge  clk) begin
                if(rst) begin
                        ID_Valid <= 1'b0;
                end
                else if(ID_Allow_in) begin
                        ID_Valid <= IF_to_ID_Valid;
                end
        end

        //IF_to_ID_Bus_reg
        always @(posedge clk) begin
                if(IF_to_ID_Valid & ID_Allow_in) begin
                        IF_to_ID_Bus_reg <= IF_to_ID_Bus;
                end
        end



//组合逻辑
        //DataPath (IF --> ID)
        assign {Instruction, //63:32
                PC           //31:0
                } = IF_to_ID_Bus_reg;


        //DataPath (WB --> Reg_File)
        assign {RF_wen, //37:37
                RF_waddr, //36:32
                RF_wdata //31:0
                } = WB_to_RegFile_Bus;


        //DataPath (WB|EX|MEM --> ID)
        assign {rdw_EX_addr_valid, rdw_EX_data_valid, rdw_EX_addr, rdw_EX_data} = rdw_EX_Bus;
        assign {rdw_MEM_addr_valid, rdw_MEM_data_valid, rdw_MEM_addr, rdw_MEM_data} = rdw_MEM_Bus;
        assign {rdw_WB_addr_valid, rdw_WB_data_valid, rdw_WB_addr, rdw_WB_data} = rdw_WB_Bus;
        

        //Instruction Decode
	assign {funct7, rt, rs, funct3, rd, opcode} = Instruction;

	assign OP_IMM	= opcode[6:0] == 7'b0010011;	
	assign LUI	= opcode[6:0] == 7'b0110111;
	assign AUIPC	= opcode[6:0] == 7'b0010111;
	assign OP_REG	= opcode[6:0] == 7'b0110011;
	assign JAL	= opcode[6:0] == 7'b1101111;
	assign JALR	= opcode[6:0] == 7'b1100111;
	assign BRANCH	= opcode[6:0] == 7'b1100011;
	assign LOAD	= opcode[6:0] == 7'b0000011;
	assign STORE	= opcode[6:0] == 7'b0100011;

        //MULTIPLY Instruction
	assign MULTIPLE = OP_REG & funct7[0];

        //Instruction Type
	assign R_Type = OP_REG;
	assign I_Type = OP_IMM | JALR | LOAD; //JALR指令和LOAD类型的指令是I_Type的格式
	assign S_Type = STORE;
	assign B_Type = BRANCH;
	assign U_Type = LUI | AUIPC; //LUI和AUIPC是U_Type的格式
	assign J_Type = JAL;

        //Control Signals
        assign Branch 	= B_Type;
	assign MemtoReg	= LOAD;
	assign ALUSrc	= I_Type | S_Type | U_Type; //I_Type和S_Type的ALU或Shifter操作来源是立即数
	assign ShiftSrc = I_Type | S_Type; 
        
	assign WB_wen	= (J_Type | I_Type | R_Type | U_Type); //只有S_Type和B_Type不用写回
	assign ALUEn	= (OP_REG | OP_IMM) & (~MULTIPLE) & (funct3[1] | ~funct3[0]) | JALR | LOAD | S_Type | B_Type;
	assign ShiftEn	= (OP_REG | OP_IMM) & (~MULTIPLE) & (~funct3[1] & funct3[0]);
        assign MULEn 	= MULTIPLE;

        assign MEM_wen = STORE | LOAD;

        
        //Extend Immediate (要实现的RISCV32中的指令的立即数扩展均是有符号扩展,包括与操作，或操作，异或操作)
	assign imm = {(32){U_Type}} & {Instruction[31:12], 12'b0} | 
		     {(32){J_Type}} & {{(12){Instruction[31]}}, Instruction[19:12], Instruction[20], Instruction[30:21],1'b0} |
		     {(32){B_Type}} & {{(20){Instruction[31]}}, Instruction[7], Instruction[30:25], Instruction[11:8], 1'b0} | 
		     {(32){I_Type}} & {{(20){Instruction[31]}}, Instruction[31:20]} | 
		     {(32){S_Type}} & {{(20){Instruction[31]}}, Instruction[31:25], Instruction[11:7]};
                

        //ALUop
        assign ALUop = ({(3){OP_IMM | OP_REG}} & {
				(funct3 == 3'b100) | (funct3 == 3'b010) | (funct3 == 3'b000 && funct7[5] && opcode[5]),	//xor slt sub类型操作首位为1，其它为0
				~funct3[2],										//and, or, xor类型操作第二位为0，其它为1
				funct3[1] & ~(funct3[0] & funct3[2])							//or, slt, sltu类型操作第三位为1，其它为0
			} | 
			{(3){STORE | LOAD | JALR | U_Type}} & 3'b010 |						//add 010
	  		{(3){BRANCH}} & {~funct3[1], 1'b1, funct3[2]});					//sub 110 slt 111 sltu 011



        //Shiftop
	assign Shiftop = {funct3[2],funct7[5]}; //funct3[2]代表左移右移,funct7[5]代表逻辑移位还是算术移位


        //Reg_File_Address from Instruction
        assign RF_raddr1 = rs;
        assign RF_raddr2 = rt; 
        assign dest = rd;
                

        //Reg_File_Data Selected Signals
        assign rs_from_EX  = (|rs) & rdw_EX_data_valid & (rdw_EX_addr == rs);
        assign rs_from_MEM = (|rs) & ~rs_from_EX & rdw_MEM_data_valid & (rdw_MEM_addr == rs);
        assign rs_from_WB  = (|rs) & ~rs_from_EX & ~rs_from_MEM & rdw_WB_data_valid & (rdw_WB_addr == rs);
        assign rs_from_RegFile  = ~(rs_from_EX |rs_from_MEM | rs_from_WB);

        assign rt_from_EX  = (|rt) & rdw_EX_data_valid & (rdw_EX_addr == rt);
        assign rt_from_MEM = (|rt) & ~rt_from_EX & rdw_MEM_data_valid & (rdw_MEM_addr == rt);
        assign rt_from_WB  = (|rt) & ~rt_from_EX & ~rt_from_MEM & rdw_WB_data_valid & (rdw_WB_addr == rt);
        assign rt_from_RegFile  = ~(rt_from_EX |rt_from_MEM | rt_from_WB);


        //Reg_File_Data Selected
        assign RF_Final_data1  = ({32{rs_from_EX}} & rdw_EX_data) | 
                           ({32{rs_from_MEM}} & rdw_MEM_data) |
                           ({32{rs_from_WB}} & rdw_WB_data) |
                           ({32{rs_from_RegFile}} & RF_rdata1);

        assign RF_Final_data2  = ({32{rt_from_EX}} & rdw_EX_data) | 
                           ({32{rt_from_MEM}} & rdw_MEM_data) |
                           ({32{rt_from_WB}} & rdw_WB_data) |
                           ({32{rt_from_RegFile}} & RF_rdata2);
        

        //DataPath (ID --> EX)
        assign ID_to_EX_Bus = { rs,             //164:160
                                rt,             //159:155
                                dest,           //154:150
                                RF_Final_data1, //149:118
                                RF_Final_data2, //117:86
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
                                };

        

        //HandShake Signals
        assign ID_Ready   = ~((B_Type & (~rs_from_RegFile | ~rt_from_RegFile)) |       //Branch需要得到正确的数据
                                (~rdw_EX_addr_valid & (rs_from_EX | rt_from_EX)) |     //与EX冲突 
                                (~rdw_MEM_addr_valid & (rs_from_MEM | rt_from_MEM)) |  //与MEM冲突
                                (~rdw_WB_addr_valid & (rs_from_WB | rt_from_WB))       //与WB冲突
                                );

        assign ID_Allow_in     = (!ID_Valid || ID_Ready && EX_Allow_in) & Mem_Feedback; //ID与EX握手成功
        assign ID_to_EX_Valid = ID_Valid & ID_Ready; //ID阶段工作正常


        //CLA例化 (for branch and jump)
        assign CLA_A = RF_Final_data1;
        assign CLA_B = ({32{B_Type}} & ~RF_Final_data2) |
                       ({32{JALR}} & imm);

        CLA CLA(
                .A(CLA_A),
                .B(CLA_B),
                .CIN(B_Type),
                .SF(CLA_SF),    //符号位
                .ZF(CLA_ZF),    //零标志位
                .OF(CLA_OF),    //Carryout标志位
                .CF(CLA_CF),    //Overflow标志位
                .S(CLA_result)
        );

        //Branch_or_not
        assign Branch_or_not = B_Type & (((~|funct3) & CLA_ZF) |                        //BEQ
                                        ((funct3 == 3'b001) & ~CLA_ZF) |                //BNE
                                        ((funct3 == 3'b100) & (CLA_OF ^ CLA_SF)) |      //BLT
                                        ((funct3 == 3'b101) & ~(CLA_OF ^ CLA_SF)) |     //BGE
                                        ((funct3 == 3'b110) & CLA_CF) |                 //BLTU
                                        ((&funct3) & ~CLA_CF)                           //BGEU
                                        );


        //Branch_Address & Jump_Address
        assign Branch_Address = PC + imm;
        assign Jump          = J_Type | JALR;
        assign Jump_Address   = {32{J_Type}} & (PC + imm) |
                                {32{JALR}} & (CLA_result & {~31'b0, 1'b0});

        //Branch_or_Jump_Bus
        assign Branch_or_Jump_wen        = (B_Type | Jump) & ID_Valid;
        assign Branch_or_Jump_Valid      = ID_Ready;
        assign Branch_or_Jump_PC         = ({32{Branch_or_not & ID_Ready}} & Branch_Address) |
                                           ({32{Jump & ID_Ready}} & Jump_Address) | 
                                           ({32{~(Jump & ID_Ready) & ~(Branch_or_not & ID_Ready)}} & (PC + 4));

        assign Branch_or_Jump_Bus        = {Branch_or_Jump_Valid, Branch_or_Jump_wen, Branch_or_Jump_PC};


        //传给IF的ID_Valid信号
        assign to_IF_Valid   = ID_Valid; 

        //Reg_File例化
        reg_file reg_file(
        .clk(clk),
        .raddr1(RF_raddr1),
        .raddr2(RF_raddr2),
        .rdata1(RF_rdata1),
        .rdata2(RF_rdata2),
        .waddr(RF_waddr),
        .wdata(RF_wdata),
        .wen(RF_wen)
        );

        
endmodule


//CLA
module CLA(
        input [31:0] A,
        input [31:0] B,
        input CIN,
        output SF,        //符号位
        output ZF,        //零标志位
        output CF,        //Carryout标志位
        output OF,        //Overflow标志位
        output [31:0] S  
);
        wire [32:0] cout;
        wire Cin;
        wire COUT;
        
        assign cout[0] = CIN;
        
        //并行加法器
        genvar i;
        generate 
                for(i = 0; i < 32; i = i + 1) 
                begin : CLA
                        wire p, g;
                        assign p = ~A[i] & B[i] | A[i] & ~B[i];
                        assign g = A[i] & B[i];
                        assign S[i] = ~p & cout[i] | p & ~cout[i];
                        assign cout[i + 1] = g | p & cout[i];
                end
        endgenerate 
        
        assign COUT = cout[32];
        assign Cin = cout[31];

        //SF:符号位 ZF:零标志 CF:进位标准 OF:溢出标准       
        assign SF = S[31];
        assign ZF = ~|S;
        assign CF = ~COUT;
        assign OF =  Cin ^ COUT;
endmodule







