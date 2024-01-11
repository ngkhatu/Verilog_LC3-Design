module CacheController(clock, reset, state, count, miss, rd, macc, rrdy, rdrdy, wacpt) ;
	input clock, reset, macc, rrdy, rdrdy, wacpt, miss, rd ;
	output reg [3:0] state ;
	output reg [1:0] count ;
	
	always@(posedge clock)
		if(reset || !macc) state = 4'd0 ;
		else
		case(state)
			4'd0:
				begin
				count = 2'd0 ;
				if(!rd) state = 4'd4 ;
				else if (miss) state = 4'd1 ;
				else state = 4'd0 ;
				end
			4'd1: if(rrdy) state = 4'd2 ;
			4'd2: if(rdrdy) state = 4'd3 ;
			4'd3:
				begin
				if(rdrdy) state = 4'd3 ;
				else if(count >= 3) state = 4'd8 ;
				else
					begin
					count = count + 2'd1 ;
					state = 4'd2 ;
					end
				end
			4'd4: if(wacpt) state = 4'd5 ;
			4'd5: if(!wacpt) state = 4'd6 ;
			4'd6: if(wacpt) state = 4'd7 ;
			4'd7:
				begin
				if(wacpt) state = 4'd7 ;
				else if(!miss) state = 4'd8 ;
				else state = 4'd2 ;
				end
			4'd8: state = 4'd0 ;
			default: state = 4'd0 ;
		endcase
endmodule

module ProcInterface(clock, rd, addr, dout, complete, state, miss, blockdata) ;
	input clock, rd, miss ;
	input [15:0] addr ;
	input [3:0] state ;
	input [63:0] blockdata ;
	output reg [15:0] dout ;
	output complete ;
	
	wire en ;
	reg [15:0] muxOut ;
	
	assign en = (complete && rd) ;
	assign complete = (((state == 4'd0) && (miss == 1'b0) && (rd == 1'b1)) || (state == 4'd8)) ;
	
	always@(posedge clock)
		if(en) dout <= muxOut ;
		else dout <= dout ;
	always@(addr[1:0] or blockdata)
		case(addr[1:0])
			2'd0: muxOut <= blockdata[15:0] ;
			2'd1: muxOut <= blockdata[31:16] ;
			2'd2: muxOut <= blockdata[47:32] ;
			2'd3: muxOut <= blockdata[63:48] ;
			default: muxOut <= 16'h0000 ;
		endcase
endmodule

module ValidArray(clock, reset, valid, index, state) ;
	input clock, reset ;
	input [3:0] state, index ;
	output valid ;
	
	reg [15:0] validArray ;
	wire [15:0] decoder, mux1out, mux2out ;
	
	assign decoder = 16'b0000000000000001<<index ;
	assign mux1out = (state == 4'd8) ? (decoder | validArray) : validArray ;
	assign mux2out = reset ? 16'd0 : mux1out ;
	assign valid = validArray[index] ;
	
	always@(posedge clock)
		validArray <= mux2out ;
endmodule

module CacheData(clock, state, count, valid, miss, rd, addr, din, blockdata, offdata) ;
	input clock, rd, valid ;
	input [15:0] addr, din, offdata ;
	input [1:0] count ;
	input [3:0] state ;
	output miss ;
	output [63:0] blockdata ;
	
	reg [15:0] BlockReg0, BlockReg1, BlockReg2, BlockReg3 ;
	reg [1:0] blocksel0, blocksel1, blocksel2, blocksel3 ;
	reg [15:0] mux0out, mux1out, mux2out, mux3out ;
	wire ramrd ;
	wire [73:0] data ;
	
	CacheRAM cram(data, addr[5:2], ramrd) ;
	
	assign ramrd = !(state == 4'd3 || state == 4'd5) ;
	assign miss = (!valid) || (addr[15:6] != data[73:64]) ;
	assign data = ramrd ? 74'hz : {addr[15:6], BlockReg3, BlockReg2, BlockReg1, BlockReg0} ;
	assign blockdata = data[63:0] ;
	always@(blocksel0 or offdata or din or data[15:0])
		case(blocksel0)
			2'd0: mux0out <= offdata ;
			2'd1: mux0out <= din ;
			2'd2: mux0out <= data[15:0] ;
			2'd3: mux0out <= 16'h0000 ;
			default: mux0out <= 16'h0000 ;
		endcase
	
	always@(blocksel1 or offdata or din or data[31:16])
		case(blocksel1)
			2'd0: mux1out <= offdata ;
			2'd1: mux1out <= din ;
			2'd2: mux1out <= data[31:16] ;
			2'd3: mux1out <= 16'h0000 ;
			default: mux1out <= 16'h0000 ;
		endcase
	
	always@(blocksel2 or offdata or din or data[47:32])
		case(blocksel2)
			2'd0: mux2out <= offdata ;
			2'd1: mux2out <= din ;
			2'd2: mux2out <= data[47:32] ;
			2'd3: mux2out <= 16'h0000 ;
			default: mux2out <= 16'h0000 ;
		endcase
	
	always@(blocksel3 or offdata or din or data[63:48])	
		case(blocksel3)
			2'd0: mux3out <= offdata ;
			2'd1: mux3out <= din ;
			2'd2: mux3out <= data[63:48] ;
			2'd3: mux3out <= 16'h0000 ;
			default: mux3out <= 16'h0000 ;
		endcase
		
	always@(posedge clock)
		begin
		BlockReg0 <= mux0out ;
		BlockReg1 <= mux1out ;
		BlockReg2 <= mux2out ;
		BlockReg3 <= mux3out ;	
		end
	
	always@(count or addr[1:0] or state)
		case(state)
			4'd2: case(count)
				2'd0: begin blocksel0 = 2'd0 ; blocksel1 = 2'd2 ; blocksel2 = 2'd2 ; blocksel3 = 2'd2 ; end
				2'd1: begin blocksel0 = 2'd2 ; blocksel1 = 2'd0 ; blocksel2 = 2'd2 ; blocksel3 = 2'd2 ; end
				2'd2: begin blocksel0 = 2'd2 ; blocksel1 = 2'd2 ; blocksel2 = 2'd0 ; blocksel3 = 2'd2 ; end
				2'd3: begin blocksel0 = 2'd2 ; blocksel1 = 2'd2 ; blocksel2 = 2'd2 ; blocksel3 = 2'd0 ; end
				default: begin blocksel0 = 2'd2 ; blocksel1 = 2'd2 ; blocksel2 = 2'd2 ; blocksel3 = 2'd2 ; end
			      endcase
			4'd4: case(addr[1:0])
				2'd0: begin blocksel0 = 2'd1 ; blocksel1 = 2'd2 ; blocksel2 = 2'd2 ; blocksel3 = 2'd2 ; end
				2'd1: begin blocksel0 = 2'd2 ; blocksel1 = 2'd1 ; blocksel2 = 2'd2 ; blocksel3 = 2'd2 ; end
				2'd2: begin blocksel0 = 2'd2 ; blocksel1 = 2'd2 ; blocksel2 = 2'd1 ; blocksel3 = 2'd2 ; end
				2'd3: begin blocksel0 = 2'd2 ; blocksel1 = 2'd2 ; blocksel2 = 2'd2 ; blocksel3 = 2'd1 ; end
				default: begin blocksel0 = 2'd2 ; blocksel1 = 2'd2 ; blocksel2 = 2'd2 ; blocksel3 = 2'd2 ; end
			      endcase
			default: begin blocksel0 = 2'd2 ; blocksel1 = 2'd2 ; blocksel2 = 2'd2 ; blocksel3 = 2'd2 ; end
		endcase

endmodule

module MemInterface(state, addr, din, offdata, miss, rrqst, rdacpt, wrqst) ;
	input [3:0] state ;
	input [15:0] addr, din ;
	input miss ;
	output reg rrqst, rdacpt, wrqst ;
	output [15:0] offdata ;
	
	assign offdata = ((state == 4'd1) || (state == 4'd4) || (state == 4'd6)) ? ((state == 4'd6) ? din : addr) : 16'hzzzz ;
	
	always@(state or miss)
		case(state)
			4'd0: begin rrqst = 1'b0 ; rdacpt = 1'b0 ; wrqst = 1'b0 ; end
			4'd1: begin rrqst = 1'b1 ; rdacpt = 1'b0 ; wrqst = 1'b0 ; end
			4'd2: begin rrqst = 1'b0 ; rdacpt = 1'b0 ; wrqst = 1'b0 ; end
			4'd3: begin rrqst = 1'b0 ; rdacpt = 1'b1 ; wrqst = 1'b0 ; end
			4'd4: begin rrqst = miss ; rdacpt = 1'b0 ; wrqst = 1'b1 ; end
			4'd5: begin rrqst = 1'b0 ; rdacpt = 1'b0 ; wrqst = 1'b0 ; end
			4'd6: begin rrqst = 1'b0 ; rdacpt = 1'b0 ; wrqst = 1'b1 ; end
			4'd7: begin rrqst = 1'b0 ; rdacpt = 1'b0 ; wrqst = 1'b0 ; end
			4'd8: begin rrqst = 1'b0 ; rdacpt = 1'b0 ; wrqst = 1'b0 ; end
			default: begin rrqst = 1'b0 ; rdacpt = 1'b0 ; wrqst = 1'b0 ; end
		endcase
endmodule


module UnifiedCache(clock, addr, din, rd, dout, complete,
	rrqst, rrdy, rdrdy, rdacpt, offdata, wrqst, wacpt, reset, macc);
  input clock, reset;

  // Processor interface
  input rd, macc;
  input [15:0] addr, din;
  output [15:0] dout;
  output complete;

  // Off-chip Memory Interface
  input rrdy, rdrdy, wacpt;
  output rrqst, rdacpt, wrqst;
  inout [15:0] offdata;

  // Internal Signals
  wire [3:0] state;
  wire [1:0] count;
  wire valid, miss;
  wire [63:0] blockdata;   


  CacheController ctrl(clock, reset, state, count, miss, rd, macc, 
                       rrdy, rdrdy, wacpt);
  ProcInterface procif(clock, rd, addr, dout, complete, state, miss, 
                       blockdata);
  MemInterface memif(state, addr, din, offdata, miss, rrqst, rdacpt, wrqst);
  ValidArray valarr(clock, reset, valid, addr[5:2], state);
  CacheData cdata(clock, state, count, valid, miss, rd, addr, din, 
                  blockdata, offdata);

endmodule

module CacheRAM(data, addr, rd) ;
  input [3:0] addr ;
  inout [73:0] data ;
  input rd ;
    
endmodule
