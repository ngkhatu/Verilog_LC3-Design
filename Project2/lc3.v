/***************************************
*
* COPYRIGHT \copyright 2004
* Xun Liu
* NC State University
* ALL RIGHTS RESERVED
*
* NOTES: This file contains the models
*        for the LC3 processor, off-chip
*        memory, and CacheRAM used in
*        ECE 406 Lab #4
*
* REVISION HISTORY
*    Date     Programmer    Description
*    11/10/04 Xun Liu       ECE406 Lab3 LC3
*    5/14/05  Rhett Davis   Updated for Spring'05
*    4/10/06  Rhett Davis   Updated for Lab #4
*    4/7/07   Rhett Davis   Updated for Spring'07
*
*****************************************/

module Fetch(clock, reset, state, pc, npc, rd, taddr, br_taken);
  input clock, reset, br_taken;
  input [15:0] taddr;
  input [3:0] state;
  output [15:0] pc, npc;   // current and next PC
  output rd;

  reg [15:0] ipc;        // internal PC
  wire [15:0] muxout;

  always @(posedge clock or posedge reset)
    if(reset==1)
       ipc<=16'h3000;  // always start from x3000 and cannot be changed
    else
      if(state==0)
        ipc<=muxout;
      else
        ipc<=ipc;

  assign rd=(state==7 || state==8 || state==9)?1'bz:1;
  assign pc=(state==7 || state==8 || state==9)?16'hzzzz:ipc;
  assign muxout=(br_taken)?taddr: npc;
  assign npc=ipc+1;
endmodule


module Controller(clock, reset, state, C_Control, complete);
  input clock,reset; 
  output [3:0] state;
  input [5:0] C_Control;
  input complete;
  reg [3:0] state;

  // the definition of the control signals
  wire [1:0] inst_type;
  wire pc_store;
  wire [1:0] mem_access_mode;
  wire load;

  assign {inst_type, pc_store, mem_access_mode, load}=C_Control;

  always @(posedge clock)
   if(reset)
    state=1;
   else
    case(state)
      0: state=1;	 // state: update PC
      1: if(complete) state=2; // state: fetch instruction
	 else state=1;
      2: case(inst_type) // state: decode 
           0: state=3;   // ALU operations
	   1: state=5;   // control instructions
	   2: state=6;   // data movement instructions
    	   default: state=15;  // invalid handler
         endcase
      3: state=4;        // state: execute ALU operations
      4: state=0;        // state: update register file
      5: if(pc_store)    // state: compute target PC
	   state=4;
	 else
	   state=0;
      6: case(mem_access_mode)  // state: compute memory address
	   0: state=8;  // memory indirect addressing mode
	   1: state=7;  // simple load or second load
	   2: state=9;  // simple store or second store
	   3: state=4;   // LEA
	 endcase
      7: if(!complete) state=7;       // state: read memory
	 else 
	   state=4;                   // save loaded data
      8: if(!complete) state=8;       // state: indirect address read
	 else 
            if(load) state=7;         
	    else state=9;             
      9: if(complete) state=0;	      // state: write memory
	 else state=9; 
     default: state=15;		      // state: invalid state
   endcase

endmodule


module Execute(E_Control, D_Data, npc, aluout, pcout);

  input [5:0] E_Control;
  input [47:0] D_Data;
  input [15:0] npc;
  output [15:0] aluout, pcout;
   
  wire [15:0] IR, VSR1, VSR2, offset11, offset9, offset6, imm5, trapvect8;
  wire [1:0] pcselect1, alu_control;
  wire pcselect2, op2select;
  reg [15:0] addin1, addin2, aluin1, aluin2;
  wire alucarry; 		// overflow checking not implemented


  assign {IR, VSR1, VSR2}=D_Data;
  assign {alu_control, pcselect1, pcselect2, op2select}=E_Control;

  // description
  always @(VSR1)
     aluin1=VSR1;

  always @(op2select or VSR2 or imm5)
    if(op2select)
       	aluin2=VSR2;
    else
 	aluin2=imm5;

  ALU alu(aluin1, aluin2, alu_control, aluout, alucarry);
  extension ext(IR, offset11, offset9, offset6, trapvect8, imm5);

  always @(pcselect1 or offset11 or offset9 or offset6)
    case(pcselect1)
      0: addin1=offset11;
      1: addin1=offset9;
      2: addin1=offset6;
      3: addin1=0;
    endcase
 
   always @(pcselect2 or npc or VSR1)
     if(pcselect2)
        addin2=npc;
     else
	addin2=VSR1;

  assign pcout=addin1+addin2;

endmodule

module extension(ir, offset11, offset9, offset6, trapvect8, imm5);
  input [15:0] ir;
  output [15:0] offset11, offset9, offset6, trapvect8, imm5;

  assign offset11={{5{ir[10]}}, ir[10:0]};
  assign offset9 ={{7{ir[8]}}, ir[8:0]};
  assign offset6={{10{ir[5]}}, ir[5:0]};
  assign imm5={{11{ir[4]}}, ir[4:0]};
  assign trapvect8={ {8{ir[7]}}, ir[7:0]};
endmodule //extension

module ALU(aluin1, aluin2, alu_control, aluout, alucarry);

  input [15:0] aluin1, aluin2;
  input [1:0] alu_control;
  output [15:0] aluout;
  output alucarry;
 
  reg [15:0] aluout;
  reg alucarry;

  always @(aluin1 or aluin2 or alu_control)
   case(alu_control)
    0: {alucarry,aluout}=aluin1+aluin2;
    1: {alucarry,aluout}={1'b0, aluin1&aluin2};
    2: {alucarry,aluout}={1'b0, ~aluin1};
    default: {alucarry,aluout}=~(aluin1^aluin2);
   endcase
endmodule // ALU

module MemAccess(state, M_Control, M_Data, M_Addr, memout, addr, din, dout, rd);
  input [3:0] state;
  input M_Control;
  input [15:0] M_Data;
  input [15:0] M_Addr;
  output [15:0] addr;
  output [15:0] din;
  output rd;
  input [15:0] dout;
  output [15:0] memout;

  reg [15:0] addr;           // addresses for memory address
  reg [15:0] din;            // data read from/written to memory
  reg rd;                    // read/write signal

  always @(state or M_Addr or M_Data or dout or M_Control)
    if(state==7)          // Read Memory
      begin
       	if(M_Control==0)
	  addr<=M_Addr;  // M_Control==0 means LD or LDR, addr <= desired address
       	else 
	  addr<=dout;    // M_Control==1 means LDI, addr <= data from last cycle
	din<=16'h0;      // because it's a read, din doesn't matter
        rd<=1'b1;         // rd should be high for a read
      end 
    else if(state==8)     // Read Indirect Address
      begin
	addr<=M_Addr;    // addr <= desired address
	din<=16'h0;      // because it's a read, din doesn't matter
        rd<=1'b1;         // rd should be high for a read
      end
    else if(state==9)     // Write Memory
      begin
       	if(M_Control==0)
	  addr<=M_Addr;  // M_Control==0 means ST or STR, addr <= desired address
       	else 
	  addr<=dout;    // M_Control==1 means STI, addr <= data from last cycle
	din<=M_Data;
        rd<=1'b0;         // rd should be low for a write
      end
    else                  // Other State
      begin
	addr<=16'hz;     // All memory signals should be high impedence
	din<=16'hz;
	rd<=1'bz; 
      end

   assign memout = dout;
   
endmodule // MemAccess

module Writeback(W_Control, aluout, memout, pcout, npc, DR_in);
  input [15:0] aluout, memout, pcout, npc;
  input [1:0] W_Control;
  output [15:0] DR_in;		// the data that will be stored in registerfile
  reg [15:0] DR_in;      	

  always @(W_Control or aluout or memout or pcout or npc)
    case(W_Control)
      0: DR_in<=aluout;
      1: DR_in<=memout;
      2: DR_in<=pcout;
      3: DR_in<=npc;
    endcase
endmodule

// registerfile consists of 8 general purpose registers
module RegFile(clock, sr1, d1, sr2, d2, din, dr, wr);

  input clock, wr;
  input [2:0] sr1, sr2, dr;     // source and destination register addresses
  input [15:0] din;             // data will be stored
  output [15:0] d1, d2;		// two read port output

  reg [15:0] ram [0:7] ;
  wire [15:0] R0,R1,R2,R3,R4,R5,R6,R7;
   
  assign d1 = ram[sr1];
  assign d2 = ram[sr2];
   
  always @(posedge clock)
    begin
       if (wr)
	 ram[dr]<=din;	 
    end

  // These lines are not necessary, but they allow
  // viewing of the the registers in a waveform viewer.
  // They do not affect synthesis.
  assign R0=ram[0];
  assign R1=ram[1];  
  assign R2=ram[2];
  assign R3=ram[3];  
  assign R4=ram[4];
  assign R5=ram[5];  
  assign R6=ram[6];
  assign R7=ram[7];
   
endmodule


module Decode(clock, state, dout, C_Control, E_Control, 
	      M_Control, W_Control, F_Control, D_Data, DR_in); 

  input clock;
  input [3:0] state;
  input [15:0] dout;
  input [15:0] DR_in;
  output M_Control;
  output [1:0] W_Control; 
  output [5:0] C_Control;
  output [5:0] E_Control;
  output [47:0] D_Data;
  output F_Control;
   
  //wire M_Control;
  reg M_Control;
  reg [1:0] W_Control; 

  reg [1:0] inst_type;
  reg pc_store;
  reg [1:0] mem_access_mode;
  reg load;
  reg [1:0] pcselect1, alu_control;
  reg pcselect2, op2select;
  reg br_taken;
  reg [2:0] sr1,sr2, dr;
  wire [15:0] VSR1, VSR2;

  reg [15:0] ir;
  wire en;
  reg [15:0] psr;
  wire [3:0] opcode=ir[15:12];
  wire [3:0] next_opcode=dout[15:12];

  // Register File (updated only on "Update Register File" state)
  assign en=(state==4)?1:0;
  RegFile rf (clock, sr1, VSR1, sr2, VSR2, DR_in, dr, en);

  // Instruction Register
  always @(posedge clock)
    if (state==4'd2)
      ir<=dout;
   
  // Program Status Register
  always @(posedge clock)
    // update psr when registerfile is changed (but not for JSR/JSRR)
    if(state==4'd4 && opcode!=4'b0100)
      if(DR_in[15])     // Negative
         psr<=16'h4;
      else if((|DR_in)) // Positive
	psr<=16'h1;
      else              // Zero
        psr<=16'h2;

  // definition of controls and data
  assign C_Control={inst_type, pc_store, mem_access_mode, load};
  assign E_Control={alu_control, pcselect1, pcselect2, op2select};
  assign F_Control=br_taken;
  assign D_Data={ir, VSR1, VSR2};

  always @(next_opcode)
    case (next_opcode[1:0])
      2'b00: inst_type<=2'd1; // Control Instructions
      2'b01: inst_type<=2'd0; // ALU Operations
      2'b10: inst_type<=2'd2; // Load Instructions
      2'b11: inst_type<=2'd2; // Store Instructions
    endcase // case(next_opcode[1:0])
      
  // Instruction Decode
  always @(ir or opcode or psr) 
    begin
       case(opcode[1:0])
	  2'b00: begin  // Control Instructions (BR,JMP,JSR,JSRR,RET only)
	     // C_Control and M_Control
	     // The following don't matter for Control Instructions
	     {load, mem_access_mode, M_Control} <= 4'b0;
	     // E_Control
             alu_control<=2'd0; // Doesn't matter for Control Instructions
             op2select<=1'b0; // Doesn't matter for Control Instructions
             case (opcode[3:2])
	       2'b00: begin        // BR
		  pcselect1<=2'd1; // select offset9
	          pcselect2<=1'b1; // select Next PC
	          pc_store<=1'b0;  // don't store PC
	          br_taken<=|(psr&ir[11:9]); // take branch if conditions met
	          sr1<=3'd0;       // doesn't matter for BR
	       end
	       2'b11: begin        // JMP/RET
		  pcselect1<=2'd3; // select 0
	          pcselect2<=1'b0; // select VSR1
	          pc_store<=1'b0;  // don't store PC
	          br_taken<=1'b1;  // always take branch
	          sr1<=ir[8:6];    // select register ir[8:6]
	       end
	       2'b01: if(ir[11])
	            begin            // JSR
		    pcselect1<=2'd0; // select Offset11
	            pcselect2<=1'b1; // select Next PC
	            pc_store<=1'b1;  // store PC
	            br_taken<=1'b1;  // always take branch
	            sr1<=3'd0;       // doesn't matter for JSR
	            end
	          else
	            begin            // JSRR
		    pcselect1<=2'd3; // select 0
	            pcselect2<=1'b0; // select VSR1
	            pc_store<=1'b0;  // store PC
	            br_taken<=1'b1;  // always take branch
	            sr1<=ir[8:6];    // select register ir[8:6]
	            end
	       default: begin      // Unrecognized opcode
		  pcselect1<=2'd0;
	          pcselect2<=1'b0;
                  pc_store<=1'b0;
                  br_taken<=1'b0;
                  sr1<=3'd0;
	       end
	     endcase // case(opcode[3:2])
	     // W_Control
	     W_Control<=2'd3;  // Select npc (Matters only for JSR, JSRR)
	     // Register File Control
	     dr<=3'd7; // Select R7 (Matters only for JSR, JSRR)
	     sr2<=3'd0; // Doesn't matter for Control Instructions
	  end
	  2'b01: begin // ALU Operations
	     // C_Control and M_Control
	     // The following don't matter for ALU Operations
	     {load, mem_access_mode, M_Control, pc_store} <= 5'b0;
	     // E_Control
	     case (opcode[3:2])
	       2'b00: alu_control<= 2'd0;  // ADD
	       2'b01: alu_control<=2'd1;   // AND
	       2'b10: alu_control<=2'd2;   // NOT
	       default: alu_control<=2'd0; // Unrecognized opcode
	     endcase // case(opcode[3:2])
	     pcselect1<=2'd0; // Doesn't matter for ALU Operations
	     pcselect2<=1'b0; // Doesn't matter for ALU Operations
             op2select<=~ir[5];
	     // W_Control and F_Control
	     W_Control<=2'd0;  // Writeback ALU output
             br_taken<=1'b0;   // Doesn't matter for ALU Operations
	     // Register File Control
	     dr<=ir[11:9];
	     sr1<=ir[8:6];
	     sr2<=ir[2:0];
	  end
	  2'b10: begin // Load Instructions
	     // C_Control and M_Control
	     load<=(opcode[3:2]==2'b10) ? 1 : 0;  // load=1 for LDI
             M_Control<=(opcode[3:2]==2'b10) ? 1 : 0; // M_Control=1 for LDI
	     case (opcode[3:2])
	       2'b10: mem_access_mode<=2'd0; // LDI
	       2'b11: mem_access_mode<=2'd3; // LEA
	       default: mem_access_mode<=2'd1; // LD and LDR
	     endcase // case(opcode[3:2])
	     pc_store<=1'b0;  // Doesn't matter for Load Instructions
	     // E_Control
	     alu_control<=2'd0; // Doesn't matter for Load Instructions
             if (opcode[3:2]==2'b01) 
               begin               // LDR
		  pcselect1<=2'd2; // select offset6
	          pcselect2<=1'b0; // select VSR1
	       end
	     else 
               begin               // LD, LDI, and LEA
		  pcselect1<=2'd1; // select offset9
	          pcselect2<=1'b1; // select Next PC
	       end
             op2select<=1'b0; // Doesn't matter for Load Instructions
	     // W_Control and F_Control
             if (opcode[3:2]==2'b11) // LEA
	       W_Control<=2'd2;      // Writeback Computed Memory Address
	     else                    // LD, LDR, and LDI
	       W_Control<=2'd1;      // Writeback Memory output
             br_taken<=1'b0;  // Doesn't matter for Load Instructions
	     // Register File Control
	     dr<=ir[11:9];
	     sr1<=ir[8:6];  // needed for LDR, doesn't matter for LD, LDI, LEA
	     sr2<=3'd0; // Doesn't matter for Load Instructions
	  end
	  2'b11: begin // Store Instructions (Ignore TRAP)
	     // C_Control and M_Control
	     load<=1'b0;  // load=0 for STI, doesn't matter for other ops
             M_Control<=(opcode[3:2]==2'b10) ? 1 : 0;  // M_Control=1 for STI
	     mem_access_mode<=(opcode[3])?0: 2; // mem_access_mode=0 for STI
	     pc_store<=0; // Doesn't matter for Store Instructions
	     // E_Control
	     alu_control<=2'd0; // Doesn't matter for Store Instructions
             if (opcode[3:2]==2'b01)
	       begin               // STR
		  pcselect1<=2'd2; // select offset6
	          pcselect2<=1'b0; // select VSR1
	       end
	       else begin          // ST, STI, and TRAP (not supported)
		  pcselect1<=2'd1; // select offset9
	          pcselect2<=1'b1; // select Next PC
	       end
             op2select<=1'b0; // Doesn't matter for Store Instructions
	     // W_Control and F_Control
	     W_Control<=2'd0; // Doesn't matter for Store Instructions
             br_taken<=1'b0;  // Doesn't matter for Store Instructions
	     // Register File Control
	     dr<=3'd0;        // Doesn't matter for Store Instructions
	     sr1<=ir[8:6];    // for STR, doesn't matter for ST, STR, TRAP
	     sr2<=ir[11:9];
	  end
       endcase // case(opcode[1:0])
    end

endmodule


module SimpleLC3(clock, reset, addr, din, dout, rd, macc, complete);

  input clock;
  input reset;
  output [15:0] addr, din;
  input [15:0] dout;
  output rd, macc;
  input complete;
   

  // internal variables
  wire [3:0] state;
  wire [1:0] W_Control;
  wire [15:0] aluout, memout, pcout, DR_in;
  wire M_Control;
  wire [15:0] M_Data, addr, din, dout;
  wire rd, complete;
  wire [5:0] E_Control;
  wire br_taken;
  wire [5:0] C_Control;
  wire [47:0] D_Data;
  wire reset;
  wire [15:0] npc;
  
  // modules
  Writeback wb(W_Control, aluout, memout, pcout, npc, DR_in);
  MemAccess memacc(state, M_Control, M_Data, pcout, memout, addr, din, dout, rd);
  Decode dec(clock, state, dout, C_Control, E_Control, 
	     M_Control, W_Control, br_taken, D_Data, DR_in);
  Execute exe(E_Control, D_Data, npc, aluout, pcout);
  Controller ctrl(clock, reset, state, C_Control, complete);
  Fetch fetch(clock, reset, state, addr, npc, rd, pcout, br_taken);

  assign M_Data=D_Data[15:0];
  assign macc=(state==1 || state==7 || state==9 || state==8)?1:0;

endmodule
