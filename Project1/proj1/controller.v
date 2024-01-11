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
				0: state = 1 ;					// Update PC
				1: state = complete ? 2 : 1 ;			// Fetch Instruction
				2: case(instrType) 				// Decode
					0: state = 3 ;
					1: state = 4 ;
					2: state = 5 ;
					default: state = 15 ;
				   endcase
				3: state = 9 ;					// Execute ALU Operations
				4: state = storePC ? 9 : 0 ;			// Compute Target PC
				5: case(MAM)					// Compute Memory Address
					0: state = 6 ;
					1: state = 7 ;
					2: state = 8 ;
					3: state = 9 ;
					default: state = 15 ;
				   endcase
				6: state = complete ? (Load ? 7 : 8) : 6 ;	// Indirect Address Read
				7: state = complete ? 9 : 7 ;			// Read Memory
				8: state = complete ? 0 : 8 ;			// Write Memory
				9: state = 0 ;					// Update Register File
				default: state = 15 ;				// Invalid State
			endcase
endmodule


module Controller_testBench ;
	reg clock, reset, complete ;
	reg [5:0] C_Control ;
	wire [3:0] state ;

	always@(state)
			case(state)
				0: $display($time, " 0 Update PC") ;
				1: $display($time, " 1 Fetch Instruction") ;
				2: $display($time, " 2 Decode") ;
				3: $display($time, " 3 Execute ALU Operations") ;
				4: $display($time, " 4 Compute Target PC") ;
				5: $display($time, " 5 Compute Memory Address") ;
				6: $display($time, " 6 Indirect Address Read") ;
				7: $display($time, " 7 Read Memory") ;
				8: $display($time, " 8 Write Memory") ;
				9: $display($time, " 9 Update Register File") ;
				default: $display($time, "15 Invalid State") ;
			endcase
	initial
	begin
	//$shm_open("waves.db");
  	//$shm_probe("AS");
	
	
		
	
	clock = 0; reset = 1 ; complete = 0 ; 
	#10 reset = 0 ;
	#10 C_Control = 6'b000000 ;
	#10 complete = 1 ;
	#10
	#10
	#10
	#10
	#10 complete = 0 ;
	#10 reset = 1 ; 
	#10 reset = 0 ;
	#10 C_Control = 6'b011000 ;
	#10 complete = 1 ;
	#10
	#10 
	#10 
	#10
	#10
	#10
	#10 C_Control = 6'b101000 ;
	#10
	#10
	#10 
	#10 complete = 0 ;
	#10 reset = 1 ;
	#10 reset = 0 ;
	#10 C_Control = 6'b100010 ;
	#10 complete = 1 ;
	#10 
	#10
	#10
	#10
	#10
	#10 reset =1 ; C_Control = 6'b100000 ; complete = 0 ;
	#10 reset = 0 ; complete = 1 ;
	#10
	#10
	#10
	#10
	#10
	#10
	#10
	#10 
	#10 $finish;
 	end
	always  #5 clock = ~clock ;
	Controller testController(clock, reset, state, C_Control, complete);

endmodule


