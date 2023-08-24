`timescale 1ns / 1ps

module mips32_risc(clk1,clk2);

input clk1,clk2;    //avoiding race condition by applying 2 phase clock

reg [31:0] PC,IF_ID_IR,IF_ID_NPC;   //Instruction fetch stage
reg [31:0] ID_EX_IR,ID_EX_NPC,ID_EX_A,ID_EX_B,ID_EX_Imm;  // Instruction decode stage
reg [2:0] ID_EX_type, EX_Mem_type, Mem_WB_type;
reg [31:0] EX_MEM_IR, EX_MEM_ALUout, EX_MEM_B;
reg cond; // checks if branch is eligible for execution
reg [31:0] Mem_WB_IR, Mem_WB_ALUout, Mem_WB_LMD; //Memory stage
reg [31:0] Reg_file [0:31]; //creating a register bank
reg [31:0] Mem [0:1023]; // creating a memory of space 32 x 1024

parameter ADD=6'd0, SUB=6'd1, AND = 6'd2, OR=6'd3, SLT = 6'd4, MUL = 6'd5, HLT = 6'd6, LW = 6'd7, SW = 6'd8,
ADDI = 6'd9, SUBI=6'd10, SLTI = 6'd11, BNEQZ = 6'd12, BEQZ = 6'd13;  // assigning opcodes for operations

parameter RR_ALU = 3'd0,RM_ALU = 3'd1, LOAD = 3'd2, STORE = 3'd3, BRANCH = 3'd4, HALT= 3'd5;

reg HALTED;
reg TAKEN_BRANCH;

always @(posedge clk1)

if(HALTED==0)
begin
if ((EX_MEM_IR[31:26]==BEQZ) && cond==1  || (EX_MEM_IR[31:26]==BNEQZ)&& cond==0)
begin
IF_ID_IR <= #2 Mem[EX_MEM_ALUout];
TAKEN_BRANCH <= #2 1'b1;
IF_ID_NPC <= #2 EX_MEM_ALUout + 1;
PC <= #2 EX_MEM_ALUout + 1;
end
else
begin
IF_ID_IR <= #2 Mem[PC];
IF_ID_NPC <= #2 PC + 1;
PC <= #2 PC + 1;
end
end

always @(posedge clk2)
if (HALTED==0)
begin
if (IF_ID_IR[25:21]==5'd0)
ID_EX_A <= 0;
else
ID_EX_A <= #2 Reg_file[IF_ID_IR[25:21]];
if(IF_ID_IR[20:16]==5'd0)
ID_EX_B <= 0;
else
ID_EX_B <= Mem[IF_ID_IR[20:16]];


ID_EX_NPC <= #2 IF_ID_NPC;
ID_EX_IR <= #2 IF_ID_IR;
ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}},{IF_ID_IR[15:0]}};

case(IF_ID_IR[31:26])
ADD,SUB,AND,OR,SLT,MUL: ID_EX_type <= #2 RR_ALU;
ADDI,SUBI,SLTI: ID_EX_type <= #2 RM_ALU;
LW: ID_EX_type <= #2 LOAD;
SW: ID_EX_type <= #2 STORE;
BNEQZ,BEQZ: ID_EX_type <= #2 BRANCH;
HLT: ID_EX_type <= #2 HALT;
default: ID_EX_type <= #2 HALT;   //invalid opcode
endcase
end

always @(posedge clk1)      //EX Stage
if (HALTED==0)
begin
EX_Mem_type <= #2 ID_EX_type;
EX_MEM_IR <= #2 ID_EX_IR;
TAKEN_BRANCH <= #2 0;

case (ID_EX_type)
RR_ALU: begin
        case(ID_EX_IR[31:26])  //opdcode
        ADD: EX_MEM_ALUout <= #2 ID_EX_A + ID_EX_B;
        SUB: EX_MEM_ALUout <= #2 ID_EX_A - ID_EX_B;
        AND: EX_MEM_ALUout <= #2 ID_EX_A & ID_EX_B;
        OR:  EX_MEM_ALUout <= #2 ID_EX_A | ID_EX_B;
        SLT: EX_MEM_ALUout <= #2 ID_EX_A < ID_EX_B;
        MUL: EX_MEM_ALUout <= #2 ID_EX_A * ID_EX_B;
        default: EX_MEM_ALUout <= #2 32'hxxxxxxxx;
        endcase
        end
RM_ALU: begin
        case(ID_EX_IR[31:26])
        ADDI: EX_MEM_ALUout <= #2 ID_EX_A + ID_EX_Imm;
        SUBI: EX_MEM_ALUout <= #2 ID_EX_A - ID_EX_Imm;
        SLTI: EX_MEM_ALUout <= #2 ID_EX_A < ID_EX_Imm;
        default: EX_MEM_ALUout <= #2 32'hxxxxxxxx;
        endcase
        end
LOAD,STORE: 
        begin
        EX_MEM_ALUout <= #2 ID_EX_A + ID_EX_Imm;
        EX_MEM_B <= #2 ID_EX_B;
        end
BRANCH:
        begin
        EX_MEM_ALUout <= #2 ID_EX_NPC + ID_EX_Imm;
        cond <= #2 (ID_EX_A==0);
        end

endcase
end

always @(posedge clk2)
if (HALTED==0)
begin
Mem_WB_type <= #2 EX_Mem_type;
Mem_WB_IR <= #2 EX_MEM_IR;

case(EX_Mem_type)

RR_ALU, RM_ALU: 
        Mem_WB_ALUout <= #2 EX_MEM_ALUout;
        
LOAD: Mem_WB_LMD <= #2 Mem[EX_MEM_ALUout];

STORE: if (TAKEN_BRANCH==0) //disable write option
            Mem[EX_MEM_ALUout] <= #2 EX_MEM_B;
 
endcase
end

always @(posedge clk1)
begin
if (TAKEN_BRANCH==0)
case (Mem_WB_type)
RR_ALU: Reg_file[Mem_WB_IR[15:11]] <= #2 Mem_WB_ALUout;   //destination register
RM_ALU: Reg_file[Mem_WB_IR[20:16]] <= #2 Mem_WB_ALUout;   //Reg B as the target register
LOAD: Reg_file[Mem_WB_IR[20:16]] <= #2 Mem_WB_LMD;
HALT: HALTED <= #2 1'b1;
endcase 
end

endmodule
