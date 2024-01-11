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
*    3/1/06   Rhett Davis   Changed name to Proj1
* 
*****************************************/

`include "proj1.v"

module test;

 reg clock; 
 reg reset;

 wire [15:0] addr, din, dout;
 wire rd, complete;

 always 
   #5 clock=~clock;

 initial
   begin
    $readmemh("proj1.dat",mem.ram);
    $shm_open("waves.db");  // save waveforms in this file
    $shm_probe("AS");       // saves all waveforms
    clock=0;
    reset=1;
    #23 reset=0;
    #1777
    $display("MEM[3009]=%d (35 expected)",mem.ram[16'h3009]);
    $display("MEM[300a]=%d (36 expected)",mem.ram[16'h300a]);
    $display("MEM[300b]=%h (300c expected)",mem.ram[16'h300b]);
    $display("MEM[300c]=%h (0024 expected)",mem.ram[16'h300c]);
    $finish;
  end

  SimpleLC3 dut(clock, reset, addr, din, dout, rd, complete);
  Memory mem(clock, addr, din, rd, dout, complete);

endmodule



module Memory(clock, addr, din, rd, dout, complete);
  input clock, rd;
  input [15:0] addr, din;
  output [15:0] dout;
  output complete;

  reg [15:0] ram[65535:0];
  reg [15:0] dout;
   
  assign complete=1;

  always @(posedge clock)
   if(rd) 
     begin
	dout<=ram[addr];
     end
   else
     begin
	ram[addr]<=din;
     end
endmodule



