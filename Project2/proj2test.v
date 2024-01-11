/***************************************
*
* COPYRIGHT \copyright 2004
* Xun Liu and Rhett Davis
* NC State University
* ALL RIGHTS RESERVED
*
* NOTES:
*
* REVISION HISTORY
*    Date     Programmer    Description
*    11/10/04 Xun Liu       ECE406 Lab3 LC3
*    3/26/05  Rhett Davis   Revised Lab3
*    4/10/06  Rhett Davis   Revised for Lab#4
* 
*****************************************/

`include "proj2.v"
`include "lc3.v"

module test;

 reg clock; 
 reg reset;

 // Processor Interface
 wire [15:0] addr, din, dout;
 wire rd, macc, complete;

 // Off-chip Memory Interface
 wire rrqst, rrdy, rdrdy, rdacpt, wrqst, wacpt;
 wire [15:0] data;

 always 
   #5 clock=~clock;

 initial
   begin
    $readmemh("proj2.dat",mem.ram);
    $shm_open("waves.db");  // save waveforms in this file
    $shm_probe("AS");       // saves all waveforms
    clock=0;
    reset=1;
    #23 reset=0;
    #5000
    $display("MEM[3009]=%d (35 expected)",mem.ram[16'h3009]);
    $display("MEM[300a]=%d (36 expected)",mem.ram[16'h300a]);
    $display("MEM[300b]=%h (300c expected)",mem.ram[16'h300b]);
    $display("MEM[300c]=%h (0024 expected)",mem.ram[16'h300c]);
    $finish;
  end

  SimpleLC3 proc(clock, reset, addr, din, dout, rd, macc, complete);
  UnifiedCache cache(clock, addr, din, rd, dout, complete,
	rrqst, rrdy, rdrdy, rdacpt, data, wrqst, wacpt, reset, macc);
  Memory mem(reset, rrqst, rrdy, rdrdy, rdacpt, data, wrqst, wacpt);
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



// CacheRAM is the non-synthesizable SRAM for
// the Cache.  It is used to store tags and
// data.  The size is 16x74
// tag is 10-bit
// data includes 4 words i.e., 64 bits
// 
module CacheRAM(data, addr, rd);
  input [3:0] addr;
  inout [73:0] data;
  input rd;

  reg [73:0] memarray[15:0];

  assign data=(rd==1)?memarray[addr]:74'hz;

  always @(data or addr or rd)
    if(rd==0)
      memarray[addr]=data;
    
endmodule


// The Memory module is the offchip memory.
// The handshake2 delay represents 2 handshake times.
// The mem_latency delay represents the memory latency.
// You can assume handshake2 > 2*(clock period) and mem_latency > 3*handshake2.
// This memory do not use the system clock.

`define handshake2 30
`define mem_latency 100

module Memory(reset, rrqst, rrdy, rdrdy, rdacpt, data, wrqst, wacpt);
  input rrqst, rdacpt, wrqst;
  output rrdy, rdrdy, wacpt;
  inout [15:0] data;
  input reset;
  reg rrdy, rdrdy, wacpt;

  reg [15:0] ram[65535:0];
  reg [3:0] state;
  reg flag;
  reg [15:0] readaddr, storedata;
  reg [1:0] count;
  integer debug;

  // controller
  always @(reset or rrqst or rdacpt or wrqst or state)
    if(reset)
      begin 
	count<=0;
	state<=0;
      end
    else
      case(state)
        0: case({rrqst,wrqst})
	    3: // write miss
	      begin
 #`handshake2   readaddr<=data;
 		flag<=1;
 		state<=4;
	      end
	    2: // read miss
	      begin	
 #`handshake2	readaddr<=data;
 		flag<=0;
 		state<=1;
	      end
	   1: // write hit
	      begin
 #`handshake2	readaddr=data;
 		flag=0;
 		state<=4;
	      end
	   0: begin
		readaddr<=readaddr;
		flag=0;
		state<=0;
              end
           endcase
	1: if(rrqst==0)
 #`handshake2   state<=2;
	   else
	    	state<=1;
	2: 
 #(`mem_latency-`handshake2) state<=3;
	3: if(rdacpt)
	    begin
	     if(count!=3)
     	       begin
 #`handshake2	state<=7;
               end
	     else
               begin
 #`handshake2	state<=0;
		debug=5;
               end
             count<=count+1;
	    end
	   else
            begin
	      state<=3;
            end
	4: if(wrqst==0)
 #`handshake2    state<=5;
	  else state<=4;
	5: if(wrqst)
 	    begin
 #`handshake2	storedata<=data;
    		state<=6;
	    end
	   else
	     	state<=5;
	6: if(wrqst==0)
 	     if(flag)      
 #(`mem_latency-`handshake2-`handshake2-`handshake2) 	state<=3;
	     else
 #`handshake2 	state<=0;
           else
		state<=6;
	7: begin
             if(rdacpt==0)
 #`handshake2 	state<=3;
             else
		state<=7;
	   end
      endcase

 // behavior
 always @(state or storedata)
   case(state)
     0: begin
	  rrdy<=0;
	  rdrdy<=0;
	  wacpt<=0;
      	end
     1: begin
	  rrdy<=1;
	  rdrdy<=0;
	  wacpt<=0;
      	end
     3: begin
	  rdrdy<=1;
	  rrdy<=0;
	  wacpt<=0;
	end
     4: begin
	  rrdy<=0;
	  rdrdy<=0;
	  wacpt<=1;
        end
     6: begin
	  rrdy<=0;
	  rdrdy<=0;
	  wacpt<=1;
	  ram[readaddr]<=storedata;
	end
     default: begin
	  rrdy<=0;
	  rdrdy<=0;
	  wacpt<=0;
	end
   endcase

  assign data=(state==3)? ram[{readaddr[15:2],count}] : 16'hz;

endmodule


