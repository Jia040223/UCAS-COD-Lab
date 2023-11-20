`define Branch_or_Jump_BUS_WD  33
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
        output [31:0]                            PC,
        output                                   Inst_Req_Valid,
        input                                    Inst_Req_Ready,
        //Instruction response channel
        input  [31:0]                            Instruction,
        input                                    Inst_Valid,
        output                                   Inst_Ready     
);
//声明
        //HandShake Signal
        reg         IF_Valid;
        wire        IF_Ready;
        wire        IF_Allow_in;
        wire        to_IF_Valid;
        
        //PC
        wire [31:0] PC_normal;
        wire [31:0] PC_abnormal;
        reg  [31:0] IF_PC;
        wire [31:0] PC_new;
        reg  [31:0] PC_new_reg;
        wire [31:0] IF_Instruction;
        
        //Branch or Jump
        wire        Branch_or_Jump; 
        reg         Branch_or_Jump_reg;
        reg         Branch_or_Jump_temp;
        
        //是否成功发射访存请求
        reg         Inst_Req_Succeed;


//寄存器更新
        //Branch or Jump
        always @(posedge clk) begin
                if(rst) begin
                        Branch_or_Jump_reg <= 1'b0;
                end
                else if(ID_Valid | IF_Allow_in) begin
                        Branch_or_Jump_reg <= Branch_or_Jump;
                end
        end

        always @(posedge clk) begin
                Branch_or_Jump_temp <= Branch_or_Jump;
        end
        

        //PC_new
        always @(posedge clk) begin
                if(rst) begin
                        PC_new_reg <= PC_normal;
                end
                else if (ID_Valid | (~Branch_or_Jump_reg & Branch_or_Jump_temp) | (~|IF_PC)) begin
                        PC_new_reg <= PC_new;
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

        //PC
        always @(posedge clk) begin  
                if(rst) begin
                        IF_PC <= 32'hfffffffc;
                end
                else if(Inst_Req_Valid & Inst_Req_Ready) begin
                        IF_PC <= PC_new_reg;
                end
        end
        
        //是否成功发射访存请求
        always @(posedge clk) begin
                if(IF_Allow_in) begin
                        Inst_Req_Succeed <= Inst_Req_Valid & Inst_Req_Ready;
                end

        end


//其它组合逻辑
        //Branch or Jump
        assign {Branch_or_Jump, PC_abnormal}   = Branch_or_Jump_Bus;

        //传给IF的信号是否有效
        assign to_IF_Valid                     = ~rst;

        //PC更新
        assign PC_normal                       = IF_PC + 4;
        assign PC_new                          = Branch_or_Jump ? PC_abnormal : PC_normal;

        //访存信号
        assign Inst_Req_Valid = to_IF_Valid & IF_Allow_in;
        assign Inst_Ready     = rst | (Inst_Req_Succeed & ID_Allow_in);

        //HandShake Signals (IF <-> ID)
        assign IF_Ready    = Inst_Req_Succeed & Inst_Valid & Inst_Ready; //访存请求成功且访存成功
        assign IF_Allow_in     = !IF_Valid || IF_Ready && ID_Allow_in;  //IF和ID握手成功
        assign IF_to_ID_Valid = IF_Valid & IF_Ready & ~Branch_or_Jump_reg; //非跳转分支指令且IF工作正常

        //PC输出
        assign PC             = PC_new_reg;
        
        //DataPath (IF --> ID)
        assign IF_Instruction = Instruction;
        assign IF_to_ID_Bus = {IF_Instruction, IF_PC};


endmodule

