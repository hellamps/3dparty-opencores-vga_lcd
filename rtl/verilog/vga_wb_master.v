/////////////////////////////////////////////////////////////////////
////                                                             ////
////  WISHBONE rev.B2 compliant enhanced VGA/LCD Core            ////
////  Wishbone master interface                                  ////
////                                                             ////
////  Author: Richard Herveille                                  ////
////          richard@asics.ws                                   ////
////          www.asics.ws                                       ////
////                                                             ////
////  Downloaded from: http://www.opencores.org/projects/vga_lcd ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2001, 2002 Richard Herveille                  ////
////                          richard@asics.ws                   ////
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
//  $Id: vga_wb_master.v,v 1.7 2002-02-16 10:40:00 rherveille Exp $
//
//  $Date: 2002-02-16 10:40:00 $
//  $Revision: 1.7 $
//  $Author: rherveille $
//  $Locker:  $
//  $State: Exp $
//
// Change History:
//               $Log: not supported by cvs2svn $
//               Revision 1.6  2002/02/07 05:42:10  rherveille
//               Fixed some bugs discovered by modified testbench
//               Removed / Changed some strange logic constructions
//               Started work on hardware cursor support (not finished yet)
//               Changed top-level name to vga_enh_top.v
//

`include "timescale.v"
`include "vga_defines.v"

module vga_wb_master (clk_i, rst_i, nrst_i, cyc_o, stb_o, cab_o, we_o, adr_o, sel_o, ack_i, err_i, dat_i, sint,
	ctrl_ven, ctrl_cd, ctrl_pc, ctrl_vbl, ctrl_vbsw, ctrl_cbsw, 
	cursor0_en, cursor0_xy, cursor0_ba, cursor0_ld, cursor1_en, cursor1_xy, cursor1_ba, cursor1_ld,
	VBAa, VBAb, Thgate, Tvgate,
	stat_avmp, stat_acmp, vmem_switch, clut_switch, line_fifo_wreq, line_fifo_d, line_fifo_full,
	clut_req, clut_ack, clut_adr, clut_q);

	// inputs & outputs

	// wishbone signals
	input         clk_i;    // master clock input
	input         rst_i;    // synchronous active high reset
	input         nrst_i;   // asynchronous low reset
	output        cyc_o;    // cycle output
	reg cyc_o;
	output        stb_o;    // strobe ouput
	reg stb_o;
	output        cab_o;    // consecutive address burst output
	reg cab_o;
	output        we_o;     // write enable output
	reg we_o;
	output [31:0] adr_o;    // address output
	output [ 3:0] sel_o;    // byte select outputs (only 32bits accesses are supported)
	reg [3:0] sel_o;
	input         ack_i;    // wishbone cycle acknowledge 
	input         err_i;    // wishbone cycle error
	input [31:0]  dat_i;    // wishbone data in

	output        sint;     // non recoverable error, interrupt host

	// control register settings
	input       ctrl_ven;   // video enable bit
	input [1:0] ctrl_cd;    // color depth
	input       ctrl_pc;    // 8bpp pseudo color/bw
	input [1:0] ctrl_vbl;   // burst length
	input       ctrl_vbsw;  // enable video bank switching
	input       ctrl_cbsw;  // enable clut bank switching

	input         cursor0_en; // enable hardware cursor0
	input [31: 0] cursor0_xy; // (x,y) address hardware cursor0
	input [31:11] cursor0_ba; // cursor0 video memory base address
	input         cursor0_ld; // reload cursor0 from video memory
	input         cursor1_en; // enable hardware cursor1
	input [31: 0] cursor1_xy; // (x,y) address hardware cursor1
	input [31:11] cursor1_ba; // cursor1 video memory base address
	input         cursor1_ld; // reload cursor1 from video memory

	// video memory addresses
	input [31: 2] VBAa;     // video memory base address A
	input [31: 2] VBAb;     // video memory base address B

	input [15:0] Thgate;    // horizontal visible area (in pixels)
	input [15:0] Tvgate;    // vertical visible area (in horizontal lines)

	output stat_avmp;       // active video memory page
	output stat_acmp;       // active CLUT memory page
	reg stat_acmp;
	output vmem_switch;     // video memory bank-switch request: memory page switched (when enabled)
	output clut_switch;     // clut memory bank-switch request: clut page switched (when enabled)

	// to/from line-fifo
	output        line_fifo_wreq;
	output [23:0] line_fifo_d;
	input         line_fifo_full;

	// to/from color lookup-table
	output        clut_req;  // clut access request
	input         clut_ack;  // clut access acknowledge
	output [ 8:0] clut_adr;  // clut access address
	input  [23:0] clut_q;    // clut access data in

	//
	// variable declarations
	//

	reg vmem_acc;                 // video memory access
	wire nvmem_req, vmem_ack;     // NOT video memory access request // video memory access acknowledge

	wire ImDone;                  // Done reading image from video mem 
	reg  dImDone;                 // delayed ImDone
	wire  ImDoneStrb;             // image done (strobe signal)
	reg  dImDoneStrb;             // delayed ImDoneStrb

	wire data_fifo_rreq, data_fifo_empty, data_fifo_hfull;
	wire [31:0] data_fifo_q;
	wire [23:0] color_proc_q, ssel1_q, rgb_fifo_d;
	wire        color_proc_wreq, ssel1_wreq, rgb_fifo_wreq;
	wire rgb_fifo_empty, rgb_fifo_full, rgb_fifo_rreq;
	wire ImDoneFifoQ;
	reg  dImDoneFifoQ, ddImDoneFifoQ;

	reg sclr; // synchronous clear

	wire [7:0] clut_offs; // color lookup table offset

	reg [8:0] cursor_adr;
	reg       cursor0_we, cursor1_we;

	//
	// module body
	//

	// generate synchronous clear
	always@(posedge clk_i)
		sclr <= #1 ~ctrl_ven;
	
	//
	// WISHBONE block
	//
	reg  [ 2:0] burst_cnt;                       // video memory burst access counter
	wire        burst_done;                      // completed burst access to video mem
	reg         sel_VBA;                         // select video memory base address
	reg  [31:2] vmemA;                           // video memory address 

	// wishbone access controller, video memory access request has highest priority (try to keep fifo full)
	always@(posedge clk_i)
		if (sclr)
			vmem_acc <= #1 1'b0;
		else
			vmem_acc <= #1 (!nvmem_req | (vmem_acc & !(burst_done & vmem_ack) ) ) & !ImDone;

	assign vmem_ack = ack_i;
	assign sint = err_i; // Non recoverable error, interrupt host system

	// select active memory page
	assign vmem_switch = ImDoneStrb;

	always@(posedge clk_i)
		if (sclr)
			sel_VBA <= #1 1'b0;
		else if (ctrl_vbsw)
			sel_VBA <= #1 sel_VBA ^ vmem_switch;  // select next video memory bank when finished reading current bank (and bank switch enabled)

	assign stat_avmp = sel_VBA; // assign output

	// selecting active clut page / cursor data
	// delay image done same amount as video-memory data
	vga_fifo #(4, 1) clut_sw_fifo (
		.clk(clk_i),
		.aclr(1'b1),
		.sclr(sclr),
		.d(ImDone),
		.wreq(vmem_ack),
		.q(ImDoneFifoQ),
		.rreq(data_fifo_rreq),
		.empty(),
		.hfull(),
		.full()
	);

	// clut bank switch / cursor data delay2: Account for ColorProcessor DataBuffer delay
	always@(posedge clk_i)
		if (sclr)
			dImDoneFifoQ <= #1 1'b0;
		else	if (data_fifo_rreq)
			dImDoneFifoQ <= #1 ImDoneFifoQ;

	always@(posedge clk_i)
		if (sclr)
			ddImDoneFifoQ <= #1 1'b0;
		else			
			ddImDoneFifoQ <= #1 dImDoneFifoQ;

	assign clut_switch = ddImDoneFifoQ & !dImDoneFifoQ;

	always@(posedge clk_i)
		if (sclr)
			stat_acmp <= #1 1'b0;
		else if (ctrl_cbsw)
			stat_acmp <= #1 stat_acmp ^ clut_switch;  // select next clut when finished reading clut for current video bank (and bank switch enabled)

	// generate clut-address
	assign clut_adr = {stat_acmp, clut_offs};

	// generate burst counter
	wire [3:0] burst_cnt_val;
	assign burst_cnt_val = {1'b0, burst_cnt} -4'h1;
	assign burst_done = burst_cnt_val[3];

	always@(posedge clk_i)
		if ( (burst_done & vmem_ack) | !vmem_acc)
			case (ctrl_vbl) // synopsis full_case parallel_case
				2'b00: burst_cnt <= #1 3'b000; // burst length 1
				2'b01: burst_cnt <= #1 3'b001; // burst length 2
				2'b10: burst_cnt <= #1 3'b011; // burst length 4
				2'b11: burst_cnt <= #1 3'b111; // burst length 8
			endcase
		else if(vmem_ack)
			burst_cnt <= #1 burst_cnt_val[2:0];

	//
	// generate image counters
	//

	// hgate counter
	reg  [15:0] hgate_cnt;
	reg  [16:0] hgate_cnt_val;
	reg  [1:0]  hgate_div_cnt;
	reg  [2:0]  hgate_div_val;

	wire hdone = hgate_cnt_val[16] & vmem_ack; // ????

	always@(hgate_cnt or hgate_div_cnt or ctrl_cd)
		begin
			hgate_div_val = {1'b0, hgate_div_cnt} - 3'h1;
			
			if (ctrl_cd != 2'b10)
				hgate_cnt_val = {1'b0, hgate_cnt} - 17'h1;
			else if ( hgate_div_val[2] )
				hgate_cnt_val = {1'b0, hgate_cnt} - 17'h1;
			else
				hgate_cnt_val = {1'b0, hgate_cnt};
		end

	always@(posedge clk_i)
		if (sclr)
				begin
					case(ctrl_cd) // synopsys full_case parallel_case
						2'b00: // 8bpp
							hgate_cnt <= #1 Thgate >> 2; // 4 pixels per cycle
						2'b01: //16bpp
							hgate_cnt <= #1 Thgate >> 1; // 2 pixels per cycle
						2'b10: //24bpp
							hgate_cnt <= #1 Thgate >> 2; // 4/3 pixels per cycle
						2'b11: //32bpp
							hgate_cnt <= #1 Thgate;      // 1 pixel per cycle
					endcase

					hgate_div_cnt <= 2'b10;
				end
		else if (vmem_ack)
			if (hdone)
				begin
					case(ctrl_cd) // synopsys full_case parallel_case
						2'b00: // 8bpp
							hgate_cnt <= #1 Thgate >> 2; // 4 pixels per cycle
						2'b01: //16bpp
							hgate_cnt <= #1 Thgate >> 1; // 2 pixels per cycle
						2'b10: //24bpp
							hgate_cnt <= #1 Thgate >> 2; // 4/3 pixels per cycle
						2'b11: //32bpp
							hgate_cnt <= #1 Thgate;      // 1 pixel per cycle
					endcase
					hgate_div_cnt <= #1 2'b10;
				end
			else //if (vmem_ack)
				begin
					hgate_cnt <= #1 hgate_cnt_val[15:0];

					if ( hgate_div_val[2] )
						hgate_div_cnt <= #1 2'b10;
					else
						hgate_div_cnt <= #1 hgate_div_val[1:0];
				end

	// vgate counter
	reg  [15:0] vgate_cnt;
	wire [16:0] vgate_cnt_val = {1'b0, vgate_cnt} -17'h1;
	wire vdone = vgate_cnt_val[16];

	always@(posedge clk_i)
		if (sclr)
			vgate_cnt <= #1 Tvgate;
		else if (ImDoneStrb)
			vgate_cnt <= #1 Tvgate;
		else if (hdone)
			vgate_cnt <= #1 vgate_cnt_val[15:0];

	assign ImDone = hdone & vdone;

	assign ImDoneStrb = ImDone & !dImDone;

	always@(posedge clk_i)
		begin
			dImDone <= #1 ImDone;
			dImDoneStrb <= #1 ImDoneStrb;
		end

	//
	// generate addresses
	//

	// select video memory base address
	always@(posedge clk_i)
		if (dImDoneStrb | sclr)
			if (!sel_VBA)
				vmemA <= #1 VBAa;
			else
				vmemA <= #1 VBAb;
		else if (vmem_ack)
			vmemA <= #1 vmemA +30'h1;

	// generate wishbone signals
	assign adr_o = {vmemA, 2'b00};
	wire wb_cycle = vmem_acc & !(burst_done & vmem_ack & nvmem_req) & !ImDone;

	always@(posedge clk_i or negedge nrst_i)
		if (!nrst_i)
			begin
				cyc_o <= #1 1'b0;
				stb_o <= #1 1'b0;
				sel_o <= #1 4'b1111;
				cab_o <= #1 1'b0;
				we_o  <= #1 1'b0;
			end
		else
			if (rst_i)
				begin
					cyc_o <= #1 1'b0;
					stb_o <= #1 1'b0;
					sel_o <= #1 4'b1111;
					cab_o <= #1 1'b0;
					we_o  <= #1 1'b0;
				end
			else
				begin
					cyc_o <= #1 wb_cycle;
					stb_o <= #1 wb_cycle;
					sel_o <= #1 4'b1111;   // only 32bit accesses are supported
					cab_o <= #1 wb_cycle;
					we_o  <= #1 1'b0;      // read only
				end

	// video-data buffer (temporary store data read from video memory)
	vga_fifo #(4, 32) data_fifo (
		.clk(clk_i),
		.aclr(1'b1),
		.sclr(sclr),
		.d(dat_i),
		.wreq(vmem_ack),
		.q(data_fifo_q),
		.rreq(data_fifo_rreq),
		.empty(data_fifo_empty),
		.hfull(data_fifo_hfull),
		.full()
	);

	assign nvmem_req = data_fifo_hfull;


	// hookup color processor
	vga_colproc color_proc (
		.clk(clk_i),
		.srst(sclr),
		.vdat_buffer_di(data_fifo_q),
		.ColorDepth(ctrl_cd),
		.PseudoColor(ctrl_pc),
		.vdat_buffer_empty(data_fifo_empty),
		.vdat_buffer_rreq(data_fifo_rreq),
		.rgb_fifo_full(rgb_fifo_full),
		.rgb_fifo_wreq(color_proc_wreq),
		.r(color_proc_q[23:16]),
		.g(color_proc_q[15:8]),
		.b(color_proc_q[7:0]),
		.clut_req(clut_req),
		.clut_ack(clut_ack),
		.clut_offs(clut_offs),
		.clut_q(clut_q)
	);

	// hookup data-source-selector && hardware cursor module
`ifdef VGA_HWC1	// generate Hardware Cursor1 (if enabled)
	reg scursor1_ld;
	reg scursor1_en;
	reg [31:0] scursor1_xy;

	always@(posedge clk_i)
		if (sclr)
			scursor1_ld <= #1 1'b0;
		else
			scursor1_ld <= #1 cursor1_ld | (scursor1_ld & !(ddImDoneFifoQ & !dImDoneFifoQ));

	always@(posedge clk_i)
		if (sclr)
			scursor1_en <= #1 1'b0;
		else if (scursor1_ld)
			scursor1_en <= #1 cursor1_en;

	always@(posedge clk_i)
		if (scursor1_ld)
			scursor1_xy <= #1 cursor1_xy;

	vga_curproc hw_cursor1 (
		.clk(clk_i),
		.rst_i(sclr),
		.Thgate(Thgate),
		.Tvgate(Tvgate),
		.idat(color_proc_q),
		.idat_wreq(color_proc_wreq),
		.cursor_xy(scursor1_xy),
		.cursor_en(scursor1_en),
		.cursor_adr(cursor_adr),
		.cursor_we(cursor1_we),
		.cursor_dat(dat_i),
		.rgb_fifo_wreq(ssel1_wreq),
		.rgb(ssel1_q)
	);

`ifdef VGA_HWC0	// generate additional signals for Hardware Cursor0 (if enabled)
	reg sddImDoneFifoQ, sdImDoneFifoQ;

	always@(posedge clk_i)
		if (ssel1_wreq)
			begin
				sdImDoneFifoQ  <= #1 dImDoneFifoQ;
				sddImDoneFifoQ <= #1 sdImDoneFifoQ;
			end
`endif

`else			// Hardware Cursor1 disabled, generate pass-through signals

	assign ssel1_wreq = color_proc_wreq;
	assign ssel1_q    = color_proc_q;

`ifdef VGA_HWC0	// generate additional signals for Hardware Cursor0 (if enabled)
	wire sddImDoneFifoQ, sdImDoneFifoQ;

	assign sdImDoneFifoQ  = dImDoneFifoQ;
	assign sddImDoneFifoQ = ddImDoneFifoQ;
`endif

`endif


`ifdef VGA_HWC0	// generate Hardware Cursor0 (if enabled)
	reg scursor0_ld;
	reg scursor0_en;
	reg [31:0] scursor0_xy;

	always@(posedge clk_i)
		if (sclr)
			scursor0_ld <= #1 1'b0;
		else
			scursor0_ld <= #1 cursor0_ld | (scursor0_ld & !(sddImDoneFifoQ & !sdImDoneFifoQ));

	always@(posedge clk_i)
		if (sclr)
			scursor0_en <= #1 1'b0;
		else if (scursor0_ld)
			scursor0_en <= #1 cursor0_en;

	always@(posedge clk_i)
		if (scursor0_ld)
			scursor0_xy <= #1 cursor0_xy;

	vga_curproc hw_cursor0 (
		.clk(clk_i),
		.rst_i(sclr),
		.Thgate(Thgate),
		.Tvgate(Tvgate),
		.idat(ssel1_q),
		.idat_wreq(ssel1_wreq),
		.cursor_xy(scursor0_xy),
		.cursor_en(scursor0_en),
		.cursor_adr(cursor_adr),
		.cursor_we(cursor0_we),
		.cursor_dat(dat_i),
		.rgb_fifo_wreq(rgb_fifo_wreq),
		.rgb(rgb_fifo_d)
	);
`else	// Hardware Cursor0 disabled, generate pass-through signals
	assign rgb_fifo_wreq = ssel1_wreq;
	assign rgb_fifo_d = ssel1_q;
`endif

	// hookup RGB buffer (temporary station between WISHBONE-clock-domain and pixel-clock-domain)
	vga_fifo #(3, 24) rgb_fifo (
		.clk(clk_i),
		.aclr(1'b1),
		.sclr(sclr),
		.d(rgb_fifo_d),
		.wreq(rgb_fifo_wreq),
		.q(line_fifo_d),
		.rreq(rgb_fifo_rreq),
		.empty(rgb_fifo_empty),
		.hfull(rgb_fifo_full),
		.full()
	);

	assign rgb_fifo_rreq = !line_fifo_full && !rgb_fifo_empty;
	assign line_fifo_wreq = rgb_fifo_rreq;

endmodule




