`timescale 1ns/100ps

module Controller(clock, reset, state, C_Control, complete) ;
	input clock, reset ;
	output reg [3:0] state ;
	input [5:0] C_Control ;
	input complete ;
	
	wire Load ;
	wire [1:0] MAM ;
	wire storePC ;
	wire [1:0] instrType ;
	
	assign Load = C_Control[0] ;
	assign MAM = C_Control[2:1] ;
	assign storePC = C_Control[3] ;
	assign instrType = C_Control[5:4] ;
	
	always@(posedge clock)
		if(reset) state = 1 ;
		else
			case(state)
				0: state = 1 ;					// state 0 = Update PC
				1: state = complete ? 2 : 1 ;			// state 1 = Fetch Instruction
				2: case(instrType) 				// state 2 = Decode
					0: state = 3 ;
					1: state = 4 ;
					2: state = 5 ;
					default: state = 15 ;
				   endcase
				3: state = 9 ;					// state 3 = Execute ALU Operations
				4: state = storePC ? 9 : 0 ;			// state 4 = Compute Target PC
				5: case(MAM)					// state 5 = Compute Memory Address
					0: state = 6 ;
					1: state = 7 ;
					2: state = 8 ;
					3: state = 9 ;
					default: state = 15 ;
				   endcase
				6: state = complete ? (Load ? 7 : 8) : 6 ;	// state 6 = Indirect Address Read
				7: state = complete ? 9 : 7 ;			// state 7 = Read Memory
				8: state = complete ? 0 : 8 ;			// state 8 = Write Memory
				9: state = 0 ;					// state 9 = Update Register File
				default: state = 15 ;				// state 15 = Invalid State
			endcase
endmodule

module extension (output [15:0] imm5, offset6, offset9, offset11, trapvect8, input [15:0] ir) ;
	
	assign imm5[15:0] = {{11{ir[4]}},{ir[4:0]}}  ;
	assign offset6[15:0] = {{10{ir[5]}},{ir[5:0]}} ;
	assign offset9[15:0] = {{7{ir[8]}},{ir[8:0]}} ;
	assign offset11[15:0] = {{5{ir[10]}},{ir[10:0]}} ;
	assign trapvect8[15:0] = {{8{ir[7]}},{ir[7:0]}} ;

endmodule

module ALU (aluout, alucarry, aluin1, aluin2, alu_control) ;
	input [15:0] aluin1, aluin2 ;
	input [1:0] alu_control ;
	reg [16:0] tmp ;
	output reg [15:0] aluout ;
	output reg alucarry ;
	always @*
		case (alu_control)
			2'b00:
				begin
				tmp = aluin1 + aluin2 ;
				alucarry = tmp[16] ;
				aluout[15:0] = tmp[15:0] ;
				end 
			2'b01: 
				begin
				aluout = aluin1 & aluin2 ;
				alucarry = 1'b0 ;
				end
			2'b10: 
				begin
				aluout = ~aluin1 ;
				alucarry = 1'b0 ;
				end
			2'b11:
				begin
				aluout = 16'h0000 ;
				alucarry = 1'b0 ;
				end
			default:
				begin
				aluout = 16'h0000 ;
				alucarry = 1'b0 ;
				end
		endcase
endmodule

module Execute(E_Control, D_Data, npc, aluout, pcout) ;
	input [5:0] E_Control ;
	input [47:0] D_Data ;
	input [15:0] npc ;
	output [15:0] aluout, pcout ;
	wire alucarry ;
	wire PCsel_2, OP2sel ;
	wire [15:0] imm5, offset6, offset9, offset11, trapvect8, IR, VSR1, VSR2, aluin1, aluin2 ;
	wire [1:0] PCsel_1, ALU_Op_Sel ;
	reg [15:0] add1, add2 ;
	
	assign {IR, VSR1, VSR2} = D_Data ;
	assign {ALU_Op_Sel, PCsel_1, PCsel_2, OP2sel} = E_Control ;
	assign aluin1 = VSR1 ;
	
	assign aluin2 = OP2sel ? imm5 : VSR2 ;
	assign pcout = add1 + add2 ;
	
	ALU ALU(aluout, alucarry, aluin1, aluin2, ALU_Op_Sel) ;
	extension extension(imm5, offset6, offset9, offset11, trapvect8, IR) ;
	
	always@(*)
		case(PCsel_1)
			2'd0: add1 = offset6 ;
			2'd1: add1 = offset9 ;
			2'd2: add1 = offset11 ;
			2'd3: add1 = 16'd0 ;
		endcase
	
	always @(PCsel_2 or npc or VSR1)
		if(PCsel_2) add2 = VSR1;
		else add2 = npc ;
endmodule

module Fetch (clock, reset, state, pc, npc, rd, taddr, br_taken) ;
	input clock, reset, br_taken ;
	input [15:0] taddr ;
	input [3:0] state ;
	output [15:0] pc, npc ;
	output rd ;
	reg [15:0] inPC ;
	wire [15:0] mux1 ;
	
	//  "Read Memory" state = 7, "Write Memory" state = 8, "Indirect Address Read" state = 6
	assign rd = (state == 6 || state == 7 || state == 8) ? 1'bz : 1'b1 ;
	assign pc = (state == 6 || state == 7 || state == 8) ? 16'hzzzz : inPC ;
	assign npc = inPC + 1 ;

	assign mux1 = br_taken ? taddr : npc ;
	// "Update PC" state = 0
	always@ (posedge clock)
		if(reset) inPC <= 16'h3000 ;
		else
			if (state == 4'b0000) inPC <= mux1 ;
			else inPC <= inPC ;
endmodule

module MemAccess(state, M_Control, M_Data, M_Addr, memout, addr, din, dout, rd) ;
	input [3:0] state ;
	input M_Control ;
	input [15:0] M_Data, M_Addr ;
	output reg [15:0] addr, din ;
	output [15:0] memout ;
	output reg rd ;
	input [15:0] dout ;
	
	assign memout = dout ;
	
	//state 6 = read Indirect Address State
	//state 7 = read memory
	//state 8 = write memory	
	always@*
		case(state)
			6:
				begin
				addr <= M_Addr ;
				din <= 16'h0 ;
				rd <= 1'b1 ;				
				end
			7:
				begin
				if(M_Control == 0) addr <= M_Addr ;
				else addr <= dout ;
				din <= 16'h0 ;
				rd <= 1'b1 ;
				end
			8:
				begin
				if(M_Control == 0) addr <= M_Addr ;
				else addr <= dout ;
				din <= M_Data ;
				rd <= 1'b0 ;
				end
			default:
				begin
				addr <= 16'hz ;
				din <= 16'hz ;
				rd <= 1'bz ;
				end
		endcase
endmodule

module Writeback(W_Control, aluout, memout, pcout, npc, DR_in) ;
	input [15:0] aluout, memout, pcout, npc ;
	input [1:0] W_Control ;
	output reg [15:0] DR_in ;
	
	always@*
		case(W_Control)
			0: DR_in <= aluout ;
			1: DR_in <= pcout ;
			2: DR_in <= npc ;
			3: DR_in <= memout ;
		endcase
endmodule

module RegFile(clock, write, dr, sr1, sr2, DR_in, VSR1, VSR2) ;
	input clock, write ;
	input [2:0] dr, sr1, sr2 ;
	input [15:0] DR_in ;
	output [15:0] VSR1, VSR2 ;
	wire [15:0] R0, R1, R2, R3, R4, R5, R6, R7 ;	
	reg [15:0] ram [0:7] ;

	assign VSR1 = ram[sr1] ;
	assign VSR2 = ram[sr2] ;
	
	assign R0 = ram[0] ;
	assign R1 = ram[1] ;
	assign R2 = ram[2] ;
	assign R3 = ram[3] ;
	assign R4 = ram[4] ;
	assign R5 = ram[5] ;
	assign R6 = ram[6] ;
	assign R7 = ram[7] ;
	
	always@(posedge clock)
		begin
		if(write) ram[dr] <= DR_in ;
		end
endmodule

module Decode(clock, state, dout, C_Control, E_Control, M_Control, W_Control, F_Control, D_Data, DR_in) ;
	input clock ;
	input [3:0] state ;
	input [15:0] dout, DR_in ;
	output reg M_Control ;
	output F_Control ;
	output reg [1:0] W_Control ;
	output [5:0] C_Control ;
	output [5:0] E_Control ;
	output [47:0] D_Data ;
	
	// For F_Control
	reg br_taken ;
	// For C_Control
	reg [1:0] Instruction_Type, Memory_Access_Mode ;
	reg Store_PC, Load ;
	// For E_Control
	reg [1:0] ALU_Operation_Select, PC_Sel_1 ;
	reg PC_Sel_2, OP_2_Sel ;
	// For D_Data
	wire enable_IRreg ;
	reg [15:0] IR ;
	wire [3:0] opcode = IR[15:12] ;
	wire [3:0] nopcode = dout[15:12] ;
	wire [15:0] VSR1, VSR2 ;
	// For Register File (enabled at Update Register State)
	wire enable_Reg ;
	reg [2:0] DR, SR1, SR2 ;
	// For PSR
	reg [15:0] PSR ;
	wire enable_PSRreg ;
	
	
	RegFile register(clock, enable_Reg, DR, SR1, SR2, DR_in, VSR1, VSR2) ;
	
	assign F_Control = br_taken ;
	assign C_Control  = {Instruction_Type, Store_PC, Memory_Access_Mode, Load} ;
	assign E_Control = {ALU_Operation_Select, PC_Sel_1, PC_Sel_2, OP_2_Sel} ;
	assign D_Data = {IR, VSR1, VSR2} ;
	assign enable_Reg = (state == 4'd9) ? 1 : 0 ;
	assign enable_IRreg = (state == 4'd2) ? 1 : 0 ;
	
	
	// IR flip-flop
	always@(posedge clock)
		if (enable_IRreg) IR <= dout ;
		else IR <= IR ;
	
	// PSR flip-flops	
	always @(posedge clock)
    		if(state==4'd9 && opcode!=4'b0100 && DR_in[15]) PSR<=16'h4 ;		// n
		else if(state==4'd9 && opcode!=4'b0100 && (|DR_in)) PSR<=16'h1 ;	// p
		else if(state==4'd9 && opcode!=4'b0100) PSR<=16'h2 ;			// z
		else PSR <= PSR ;

	// Instruction Type decode logic	
	always@(nopcode)
		if(nopcode == 4'b0001 && dout[5] == 0) Instruction_Type <= 2'd0 ; // ADD w/ mode 0		
		else if(nopcode == 4'b0001 && (dout[5] != 0)) Instruction_Type <= 2'd0 ; // ADD w/ mode 1		
		else if(nopcode == 4'b0101 && (dout[5] == 0)) Instruction_Type <= 2'd0 ; // AND w/ mode 0		
		else if(nopcode == 4'b0101 && (dout[5] != 0)) Instruction_Type	<= 2'd0 ; // AND w/ mode 1		
		else if(nopcode == 4'b1001) Instruction_Type <= 2'd0 ; // NOT		
		else if(nopcode == 4'b0000) Instruction_Type <= 2'd1 ; // BR		
		else if(nopcode == 4'b1100) Instruction_Type <= 2'd1 ; // JMP/ RET		
		else if(nopcode == 4'b0100 && (dout[11] == 1)) Instruction_Type <= 2'd1 ; // JSR		
		else if(nopcode == 4'b0100 && (dout[11] == 0)) Instruction_Type <= 2'd1 ; // JSRR		
		else if(nopcode == 4'b0010) Instruction_Type <= 2'd2 ; // LD		
		else if(nopcode == 4'b0110) Instruction_Type <= 2'd2 ; // LDR		
		else if(nopcode == 4'b1010) Instruction_Type <= 2'd2 ; // LDI		
		else if(nopcode == 4'b1110) Instruction_Type <= 2'd2 ; // LEA		
		else if(nopcode == 4'b0011) Instruction_Type <= 2'd2 ; // ST		
		else if(nopcode == 4'b0111) Instruction_Type <=	2'd2 ; // STR		
		else if(nopcode == 4'b1011) Instruction_Type <= 2'd2 ; // STI		
		else Instruction_Type <= 2'd3 ; //any other opcode for error
	
	// Main Decode Logic	
	always@(IR or PSR or opcode)
		begin
		if(opcode == 4'b0001 && (IR[5] == 1'b0)) // ADD w/ mode 0
			begin
			DR <= IR[11:9] ;
			SR1 <= IR[8:6] ;
			SR2 <= IR[2:0] ;
			ALU_Operation_Select <= 2'd0 ;
			OP_2_Sel <= 1'b0 ;
			W_Control <= 1'b0 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b0001 && (IR[5] == 1'b1)) // ADD w/ mode 1
			begin
			DR <= IR[11:9] ;
			SR1 <= IR[8:6] ;
			ALU_Operation_Select <= 2'd0 ;
			OP_2_Sel <= 1'b1 ;
			W_Control <= 1'b0 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b0101 && (IR[5] == 1'b0)) // AND w/ mode 0
			begin
			DR <= IR[11:9] ;
			SR1 <= IR[8:6] ;
			SR2 <= IR[2:0] ;
			ALU_Operation_Select <= 2'd1 ;
			OP_2_Sel <= 1'b0 ;
			W_Control <= 1'b0 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b0101 && (IR[5] == 1'b1)) // AND w/ mode 1
			begin
			DR <= IR[11:9] ;
			SR1 <= IR[8:6] ;
			ALU_Operation_Select <= 2'd1 ;
			OP_2_Sel <= 1'b1 ;
			W_Control <= 1'b0 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b1001) // NOT
			begin
			DR <= IR[11:9] ;
			SR1 <= IR[8:6] ;
			ALU_Operation_Select <= 2'd2 ;
			W_Control <= 1'b0 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b0000) // BR
			begin
			Store_PC <= 1'b0 ;
			PC_Sel_1 <= 2'd1 ;
			PC_Sel_2 <= 1'b0 ;
			br_taken <= (|(IR[11:9] & PSR)) ;
			end		
		else if(opcode == 4'b1100) // JMP/ RET
			begin
			SR1 <= IR[8:6] ;
			Store_PC <= 1'b0 ;
			PC_Sel_1 <= 2'd3 ;
			PC_Sel_2 <= 1'b1 ;
			br_taken <= 1'b1 ;
			end		
		else if(opcode == 4'b0100 && (IR[11] == 1'b1)) // JSR
			begin
			DR <= 3'd7 ;
			Store_PC <= 1'b1 ;
			PC_Sel_1 <= 2'd2 ;
			PC_Sel_2 <= 1'b0 ;
			br_taken <= 1'b1 ;
			W_Control <= 2'd2 ;
			end		
		else if(opcode == 4'b0100 && (IR[11] == 1'b0)) // JSRR
			begin
			DR <= 3'd7 ;
			SR1 <= IR[8:6] ;
			Store_PC <= 1'b1 ;
			PC_Sel_1 <= 2'd3 ;
			PC_Sel_2 <= 1'b1 ;
			br_taken <= 1'b1 ;
			W_Control <= 2'd2 ;
			end		
		else if(opcode == 4'b0010) // LD
			begin
			DR <= IR[11:9] ;
			Memory_Access_Mode <= 2'd1 ;
			M_Control <= 1'b0 ;
			PC_Sel_1 <= 2'd1 ;
			PC_Sel_2 <= 2'b0 ;
			W_Control <= 2'd3 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b0110) // LDR
			begin
			DR <= IR[11:9] ;
			SR1 <= IR[8:6] ;
			Memory_Access_Mode <= 2'd1 ;
			M_Control <= 1'b0 ;
			PC_Sel_1 <= 2'd0 ;
			PC_Sel_2 <= 2'b1 ;
			W_Control <= 2'd3 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b1010) // LDI
			begin
			DR <= IR[11:9] ;
			Memory_Access_Mode <= 2'd0 ;
			Load <= 1'b1 ;
			M_Control <= 1'b1 ;
			PC_Sel_1 <= 2'd1 ;
			PC_Sel_2 <= 2'b0 ;
			W_Control <= 2'd3 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b1110) // LEA
			begin
			DR <= IR[11:9] ;
			Memory_Access_Mode <= 2'd3 ;
			PC_Sel_1 <= 2'd1 ;
			PC_Sel_2 <= 2'b0 ;
			W_Control <= 2'd1 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b0011) // ST
			begin
			SR2 <= IR[11:9] ;
			Memory_Access_Mode <= 2'd2 ;
			M_Control <= 1'b0 ;
			PC_Sel_1 <= 2'd1 ;
			PC_Sel_2 <= 2'b0 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b0111) // STR
			begin
			SR1 <= IR[8:6] ;
			SR2 <= IR[11:9] ;
			Memory_Access_Mode <= 2'd2 ;
			M_Control <= 1'b0 ;
			PC_Sel_1 <= 2'd0 ;
			PC_Sel_2 <= 2'b1 ;
			br_taken <= 1'b0 ;
			end		
		else if(opcode == 4'b1011) // STI
			begin
			SR2 <= IR[11:9] ;
			Load <= 1'b0 ;
			M_Control <= 1'b0 ;
			Memory_Access_Mode <= 2'd0 ;
			M_Control <= 1'b1 ;
			PC_Sel_1 <= 2'd1 ;
			PC_Sel_2 <= 2'b0 ;
			br_taken <= 1'b0 ;
			end		
		else //any other opcode
			begin
			//ALU_Operation_Select <= 0 ;
			end
		end
endmodule

module SimpleLC3(clock, reset, addr, din, dout, rd, complete) ;
	input clock, reset, complete ;
	input [15:0] dout ;
	output [15:0] addr, din ;
	output rd ;
	
	wire F_Control, M_Control ;
	wire [5:0] E_Control, C_Control ;
	wire [47:0] D_Data ;
	wire [1:0] W_Control ;
	wire [3:0] state ;
	wire [15:0] npc, pcout,aluout, memout, din, dout, DR_in ;
	
	Controller Controller_block(clock, reset, state, C_Control, complete) ;
	Fetch Fetch_block(clock, reset, state, addr, npc, rd, pcout, F_Control) ;
	Execute Execute_block(E_Control, D_Data, npc, aluout, pcout) ;
	MemAccess MemAccess_block(state, M_Control, D_Data[15:0], pcout, memout, addr, din, dout, rd) ;
	Writeback Writeback_block(W_Control, aluout, memout, pcout, npc, DR_in) ;
	Decode Decode_block(clock, state, dout, C_Control, E_Control, M_Control, W_Control, F_Control, D_Data, DR_in) ;
endmodule
