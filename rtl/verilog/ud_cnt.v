/////////////////////////////////////////////////////////////////////
////                                                             ////
////  Universal Up/Down counter, library module                  ////
////                                                             ////
////                                                             ////
////  Author: Richard Herveille                                  ////
////          richard@asics.ws                                   ////
////          www.asics.ws                                       ////
////                                                             ////
////                                                             ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2001 Richard Herveille                        ////
////                    richard@asics.ws                         ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////

//  CVS Log
//
//  $Id: ud_cnt.v,v 1.3 2001-11-14 11:45:25 rherveille Exp $
//
//  $Date: 2001-11-14 11:45:25 $
//  $Revision: 1.3 $
//  $Author: rherveille $
//  $Locker:  $
//  $State: Exp $
//
// Change History:
//               $Log: not supported by cvs2svn $


/////////////////////////////
// general purpose counter //
/////////////////////////////

`include "timescale.v"

module ud_cnt (clk, nReset, rst, cnt_en, ud, nld, d, q, resd, rci, rco);
	// parameter declaration
	parameter SIZE  = 8;
	// inputs & outputs
	input             clk;    // master clock
	input             nReset; // asynchronous active low reset
	input             rst;    // synchronous active high reset
	input             cnt_en; // count enable
	input             ud;     // up/not down
	input             nld;    // synchronous active low load
	input  [SIZE-1:0] d;      // load counter value
	output [SIZE-1:0] q;      // current counter value
	input  [SIZE-1:0] resd;   // initial data after/during reset
	input             rci;    // carry input
	output            rco;    // carry output

	// variable declarations
	reg  [SIZE-1:0] Qi;  // intermediate value
	wire [SIZE:0]   val; // carry+result

	//
	// Module body
	//

	assign val = ud ? ( {1'b0, Qi} + rci) : ( {1'b0, Qi} - rci);

	always@(posedge clk or negedge nReset)
	begin
		if (~nReset)
			Qi <= #1 resd;
		else if (rst)
			Qi <= #1 resd;
		else	if (~nld)
			Qi <= #1 d;
		else if (cnt_en)
			Qi <= #1 val[SIZE-1:0];
	end

	// assign outputs
	assign q = Qi;
	assign rco = val[SIZE];
endmodule
