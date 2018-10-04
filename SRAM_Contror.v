`timescale 1 ns / 100 ps
`define SIM
`define IS61LV25616AL_10TL
`define SYS_CLK    100000000
`define BURST    16
`define BURST_WIDTH    8
module sram_ctrl(
                            sys_clk,
                            sys_rst_n,
                            //read
                            sys_rd_addr_i,
                            rreq_i,
                            sys_data_o,
                            sram_rd_ack_o,
                            sram_rd_valid_o,
                            //write
                            wreq_i,
                            sys_wr_addr_i,
                            sys_data_i,
                            sram_wr_valid_o,
                            sram_wr_ack_o,
                            //sram
                            sram_ce_n,
                            sram_oe_n,
                            sram_we_n,
                            sram_lb_n,
                            sram_ub_n,
                            sram_addr,
                            sram_data
                            );
`ifdef IS61LV25616AL_10TL
    `define DSIZE    16
    `define ASIZE     18
`endif
input sys_clk;
input sys_rst_n;
//read
input [`ASIZE-1:0] sys_rd_addr_i;
input rreq_i;
output [`DSIZE-1:0] sys_data_o;
output sram_rd_ack_o;
output sram_rd_valid_o;
//write
input [`ASIZE-1:0] sys_wr_addr_i;
input wreq_i;
input [`DSIZE-1:0] sys_data_i;
output sram_wr_ack_o;
output sram_wr_valid_o;
//sram
output sram_ce_n;
output sram_oe_n;
output sram_we_n;
output sram_lb_n;
output sram_ub_n;
output [`ASIZE-1:0] sram_addr;
inout [`DSIZE-1:0] sram_data;
//command
parameter    CMD_NOP = 5'b01000, 
                CMD_READ = 5'b10000,
                CMD_WRITE = 5'b00100;
reg [4:0] cmd_r = CMD_NOP;
assign {sram_we_n,sram_ce_n,sram_oe_n,sram_lb_n,sram_ub_n} = cmd_r; 
//FSM PARAMS
`ifdef SIM
    parameter ST_WIDTH = 40;
    parameter IDLE = "IDLE.",
                    READ = "READ.",
                    RD = "RD...",
                    END = "END..",
                    WR = "WR...";
`else
    `define FSM    5
    parameter ST_WIDTH = 5;
    parameter IDLE = `FSM'b0_0001,
                    READ = `FSM'b0_0010,
                    RD = `FSM'b0_0100,
                    END = `FSM'b0_1000,
                    WR = `FSM'b1_0000;
`endif
//capture the posedge of rreq
reg rreq_r = 0;
always @ (posedge sys_clk) begin
if(sys_rst_n == 1'b0) rreq_r <= 0;
else rreq_r <= rreq_i;
end
wire do_rreq = rreq_i & ~rreq_r;
//generate the rd_start signal
reg rd_start = 0;
always @ (posedge sys_clk) begin
if(sys_rst_n == 1'b0) rd_start <= 0;
else if(sram_rd_ack_o == 1'b1) rd_start <= 0;
else if(do_rreq) rd_start <= 1;
else rd_start <= rd_start;
end
//capture the posedge of wreq
reg wreq_r = 0;
always @ (posedge sys_clk) begin
if(sys_rst_n == 1'b0) wreq_r <= 0;
else wreq_r <= wreq_i;
end
wire do_wreq = wreq_i & ~wreq_r;
//generate the rd_start signal
reg wr_start = 0;
always @ (posedge sys_clk) begin
if(sys_rst_n == 1'b0) wr_start <= 0;
else if(sram_wr_ack_o == 1'b1) wr_start <= 0;
else if(do_wreq) wr_start <= 1;
else wr_start <= wr_start;
end
//FSM register
reg [`BURST_WIDTH-1:0] bit_cnt = 0;
reg [ST_WIDTH-1:0] c_st = IDLE;
reg [ST_WIDTH-1:0] n_st = IDLE;
reg link = 0;    //0:read while 1:write

reg [`ASIZE-1:0] sram_addr = 0;
//fsm-1
always @ (posedge sys_clk) begin
if(1'b0 == sys_rst_n) c_st <= IDLE;
else c_st <= n_st;
end
//fsm-2
always @ (*) begin
    case(c_st)
    IDLE:begin
                if(rd_start == 1'b1) begin
                                            n_st = READ;end
                else if(wr_start == 1'b1) begin
                                            n_st = WR;end
                else begin
                        n_st = IDLE;end
            end
    READ:n_st = RD;
    RD:n_st = (bit_cnt == `BURST)?END:RD;
    END:n_st = IDLE;
    WR:n_st = (bit_cnt == `BURST)?END:WR;
    default:n_st = IDLE;
    endcase
end
//fsm-3
always @ (posedge sys_clk) begin
if(sys_rst_n == 1'b0) begin
                                bit_cnt <= 0;
                                link <= 0;
                                sram_addr <= `ASIZE'h3FFFF;
                                cmd_r <= CMD_NOP;
                                end
else begin
        case(n_st)
        IDLE:begin
                                bit_cnt <= 0;
                                link <= 0;
                                sram_addr <= sram_addr;
                                cmd_r <= CMD_NOP;
                                end
        READ:begin
                    bit_cnt <= bit_cnt;
                    sram_addr <= sys_rd_addr_i;
                    link <=0;
                    cmd_r <= CMD_READ;
                    end
        RD:begin
                    bit_cnt <= (bit_cnt == `BURST)?`BURST_WIDTH'd0:bit_cnt + 1'd1;
                    link <= 0;
                    sram_addr <= (bit_cnt == `BURST-1)?sram_addr:sram_addr + 1'd1;
                    cmd_r <= CMD_READ;
                    end
        END:begin
                    bit_cnt <= 0;
                    link <= 0;
                    sram_addr <= sram_addr;
                    cmd_r <= CMD_NOP;
                    end
        WR:begin
                    bit_cnt <= (bit_cnt == `BURST)?`BURST_WIDTH'd0:bit_cnt + 1'd1;
                    sram_addr <= (bit_cnt == `BURST)?sram_addr:sram_addr + 1'd1;
                    link <=1;
                    cmd_r <= CMD_WRITE;
                    end
        default:begin
                                bit_cnt <= 0;
                                link <= 0;
                                sram_addr <= `ASIZE'h3FFFF;
                                cmd_r <= CMD_NOP;end
        endcase
        end
end
//generate sys_data_o
reg [`DSIZE-1:0] sys_data_o = 0;
always @ (*) begin
if(c_st == RD) sys_data_o <= sram_data;
else sys_data_o <= sys_data_o;
end
//generate sram_data_r
reg [`DSIZE-1:0] sram_data_r = 0;
always @ (*) begin
if(c_st == WR) sram_data_r <= sys_data_i;
else sram_data_r <= sram_data_r;
end
//assign
assign sram_data = (link == 1'b1)?sram_data_r:16'hzzzz;
assign sram_rd_ack_o = ((c_st == END)&&(rd_start == 1'b1))?1'b1:1'b0;
assign sram_rd_valid_o = (c_st == RD)?1'b1:1'b0;
assign sram_wr_ack_o = ((c_st == END)&&(wr_start == 1'b1))?1'b1:1'b0;
assign sram_wr_valid_o = (c_st == WR)?1'b1:1'b0;

endmodule