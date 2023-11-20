`define MEM_TO_WB_BUS_WD 70
`define WB_TO_RF_BUS_WD  38
`define RDW_BUS_WD       39

module WB_State(
        input                            clk,
        input                            rst,
        //Allow_in
        output                           WB_Allow_in,
        //from MEM
        input                            MEM_to_WB_Valid,
        input  [`MEM_TO_WB_BUS_WD - 1:0] MEM_to_WB_Bus,
        //to rf
        output [`WB_TO_RF_BUS_WD - 1 :0] WB_to_RegFile_Bus,
        //rdw to id
        output [`RDW_BUS_WD - 1      :0] rdw_WB_Bus,
        //inst_retire
        output                           retired,
        output [69                   :0] inst_retire
);

//声明
        //HandShake Signals
        reg  WB_Valid;
        wire WB_Ready;
        reg  [`MEM_TO_WB_BUS_WD - 1:0] MEM_to_WB_Bus_reg;

        //Other Signals from MEM
        wire            WB_wen;
        wire [4:0]      RF_waddr;
        wire [31:0]     final_result;
        wire [31:0]     PC;
        
        //Reg_File
        wire            RF_wen;
        wire [31:0]     RF_wdata;

        //Inst_Retired
        wire [69:0]     retire_data;
        reg  [69:0]     inst_retire;
        reg  [69:0]     Temp_inst_retire;



//时序逻辑
        //WB_Valid
        always @(posedge clk) begin
                if(rst) begin
                        WB_Valid <= 1'b0;
                end
                else if(WB_Allow_in)begin
                        WB_Valid <= MEM_to_WB_Valid;
                end
        end


        //MEM_to_WB_Bus_reg
        always @(posedge clk) begin
                if(MEM_to_WB_Valid & WB_Allow_in) begin
                        MEM_to_WB_Bus_reg <= MEM_to_WB_Bus;
                end
        end


        //Inst_retired(防止连续两个周期内RF_wen均拉高，无其它作用, 希望框架尽快改善)
        always @(posedge clk) begin
                if (Temp_inst_retire[69]) begin 
                        inst_retire <= Temp_inst_retire;
                end
                else if(~(inst_retire[69] & RF_wen)) begin
                        inst_retire <= retire_data;
                end
                else begin
                        inst_retire <= 70'b0;
                end
        end

        always @(posedge clk) begin
                if(inst_retire[69] & RF_wen) begin
                        Temp_inst_retire <= retire_data;
                end
                else begin
                        Temp_inst_retire <= 70'b0;
                end
        end



//组合逻辑
        //DataPath (MEM --> WB)
        assign {WB_wen,
                RF_waddr,
                final_result,
                PC
                } = MEM_to_WB_Bus_reg;


        //DataPath (WB --> ID)
        assign rdw_WB_Bus =   { 1'b1,           //38:38
                                RF_wen,         //37:37
                                RF_waddr,       //36:2
                                final_result    //31:0
                                };
        

        //HandShake Signals
        assign WB_Ready = 1'b1;
        assign WB_Allow_in  = !WB_Valid || WB_Ready;


        //RF_Write
        assign RF_wen   = WB_Valid & WB_wen;
        assign RF_wdata = final_result;
        

        //DataPath (WB --> RF)
        assign WB_to_RegFile_Bus = {RF_wen,     //37:37
                                    RF_waddr,   //36:32
                                    RF_wdata    //31:0
                                    };


        //retired_instruction
        assign retired   = WB_Valid;
        assign retire_data = {RF_wen,             //69:69
                            RF_waddr,             //68:64
                            final_result,         //63:32
                            PC                    //31:0
                            };
        
endmodule
