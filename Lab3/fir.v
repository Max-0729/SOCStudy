module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
	// AXI-Lite
    output  reg                     awready,
    output  reg                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
	
    output  reg                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  reg                     rvalid,
    output  reg [(pDATA_WIDTH-1):0] rdata,   
	// AXI-STREAM
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  reg                     ss_tready, 
    input   wire                     sm_tready, 
    output  reg                     sm_tvalid, 
    output  reg [(pDATA_WIDTH-1):0] sm_tdata, 
    output  reg                     sm_tlast, 
    
    // bram for tap RAM
    output  reg [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  reg [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg [3:0]               data_WE,
    output  wire                     data_EN,
    output  reg [(pDATA_WIDTH-1):0] data_Di,
    output  reg [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n,
	output  reg						test_flag
);
/////// bram declare
// bram11 data_ram	(.CLK(axis_clk), .WE(data_WE), .EN(data_EN), .Di(data_Di), .Do(data_Do),.A(data_A));
// bram11 tap_ram	(.CLK(axis_clk), .WE(tap_WE), .EN(tap_EN), .Di(tap_Di), .Do(tap_Do),.A(tap_A));

assign  tap_EN =1'b1;
assign  data_EN =1'b1;
reg ap_start;
reg ap_done;
reg ap_idle;
///////////////////////reg and wire declare
reg [2:0] current_state;
reg [2:0] next_state;
reg [3:0] coef_counter;
reg [3:0] check_counter;
reg check_flag;
reg [31:0] data_length;
reg [31:0] counter;
reg [3:0] cal_counter;
reg idle_flag;
reg signed[31:0] total_data;
reg idle_buffer;
wire [31:0] loca;
parameter	IDLE				=0,
			READ_COEF			=1,
			READ_COEF_CHECK		=2,
			READ_STREAM			=3,
			CAL					=4;
			
always @(posedge axis_clk )begin
	if(!axis_rst_n)begin
		current_state <= IDLE;
	end
	else begin
		current_state <= next_state;
	end
end

always @(*)begin
	case(current_state)
		IDLE:
			if	(idle_flag)			next_state = READ_COEF;				
			else					next_state = IDLE;						
		READ_COEF:
			if(coef_counter =='d11)	next_state = READ_COEF_CHECK;
			else 					next_state = READ_COEF;
		READ_COEF_CHECK:
			if(check_counter=='d11 && awaddr ==12'h00 &&  wdata ==32'h0000_0001)	next_state = READ_STREAM;
			else																next_state = READ_COEF_CHECK;
		READ_STREAM:
			if(counter=='d600 )			next_state =IDLE;
			else if(sm_tready)			next_state = CAL;
			else					next_state = READ_STREAM;
		CAL:
			
			if(cal_counter =='d12)	next_state =READ_STREAM;
			else 					next_state = CAL;
		default: 					next_state = IDLE ;
	endcase
end
//////////////idle_flag

always @(posedge axis_clk )begin
	if(!axis_rst_n)begin
		idle_flag <= 0;
	end
	else if( (awaddr ==16) && awvalid==1 && wvalid==1) begin
		idle_flag <= 1;
	end
	else begin
		idle_flag <= 0;
	end

end



//////// data_length
always @(posedge axis_clk )begin
	if(!axis_rst_n)begin
		data_length <= 0;
	end
	else if(current_state == IDLE && awvalid && wvalid) begin
		data_length <= wdata;
	end

end


/////////// tap_data counter
always @(posedge axis_clk )begin
	if(!axis_rst_n)begin
		coef_counter <= 0;
	end
	else if(current_state == READ_COEF && awvalid && wvalid) begin
		coef_counter <= coef_counter+1;
	end
	else if(current_state != READ_COEF)begin
		coef_counter <= 0;
	end
end
//////////////tap_data check_counter

always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		check_counter <=0;
	end
	else if (current_state == READ_COEF_CHECK && arvalid && rready&&rvalid)begin
		check_counter <= check_counter+1;
	
	end
	else if (current_state != READ_COEF_CHECK)begin
		check_counter<=0;
	end

end


////////////// bram tap_data tap_WE 1:write data 0:read data
always@(*)begin
	if(current_state == READ_COEF && awvalid && wvalid)begin
		tap_WE = 4'b1111;
	
	end
	else begin
		tap_WE = 4'b0000;
	
	end

end
////////////////////address
always@(*)begin
	if(current_state == READ_COEF && awvalid && wvalid)begin
		tap_A = awaddr-12'h20;
	end
	else if (current_state == READ_COEF_CHECK && arvalid && rready)begin
		tap_A = check_counter*4;
	end
	else if (current_state == CAL && cal_counter <'d11)begin
		tap_A = cal_counter*4;
	end
	else begin
		tap_A =0;
	end

end
/////////////////////data
always@(*)begin
	if(current_state == READ_COEF && awvalid && wvalid)begin
		tap_Di = wdata;
	end
	else begin
		tap_Di =0;
	end

end

always@(*)begin
	if(current_state == IDLE && awvalid && wvalid)begin
		wready = 1;
		awready =1;
	end
	else if(current_state == READ_COEF && awvalid && wvalid)begin
		wready = 1;
		awready =1;
	end
	else if (current_state == READ_COEF_CHECK && awaddr ==12'h00 &&  wdata ==32'h0000_0001)begin
		wready = 1;
		awready =1;
	end
	else begin
		wready =0;
		awready =0;
	end

end

always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		ap_start<=0;
	
	end
	else if (check_counter=='d11 && awaddr ==12'h00 &&  wdata ==32'h0000_0001)begin
		ap_start <=1;
	end
	else begin
		ap_start<=0;
	end
end

always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		idle_buffer<=0;
	
	end
	else if (sm_tlast && sm_tready)begin
		idle_buffer<=1;
	end
	else begin
		idle_buffer<=0;
	end
	
end
always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		ap_idle<=1;
	
	end
	else if (ap_start)begin
		ap_idle <=0;
	end
	else if (idle_buffer )begin
		ap_idle<=1;
	end
end
always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		ap_done<=0;
	
	end

	else if (sm_tlast && sm_tready)begin
		ap_done<=1;
	end

	else if(awaddr == 12'h00)begin
		ap_done<=0;
	end
end

always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		check_flag<=0;
	
	end
	else if (current_state == READ_COEF_CHECK && arvalid && rready && !rvalid)begin
		check_flag <=1;
	end
	else begin
		check_flag<=0;
	end
end

always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		rvalid<=0;
		rdata <=0;
	end	
	else if(check_flag)begin
		rvalid<=1;
		rdata <=tap_Do;
	end
	else if (awaddr ==12'h00)begin
		rvalid<=1;
		rdata <={29'b0,ap_idle,ap_done,ap_start};	
	
	end
	else begin
		rvalid 	<=0;
		rdata 	<=0;
	end

end

///////////////////////////////////////////////////////////////////////// read stream and calculation
always @(posedge axis_clk )begin
	if(!axis_rst_n)begin
		counter <= 0;
	end
	else if(current_state == READ_STREAM && ss_tvalid ) begin
		counter <= counter+1;
	end
	else if(current_state == IDLE)begin
		counter <= 0;
	end
end



////////////// bram dram_data tap_WE 1:write data 0:read data
always@(*)begin
	if(current_state == READ_COEF && awvalid && wvalid)begin
		data_WE = 4'b1111;
	
	end
	else if (current_state == READ_STREAM && ss_tvalid)begin
		data_WE = 4'b1111;
	end
	else begin
		data_WE = 4'b0000;
	
	end

end
////////////////////address
assign loca = (counter-1 >=cal_counter)? counter-cal_counter-1:'d10;
always@(*)begin
	if(current_state == READ_COEF && awvalid && wvalid)begin
		data_A = awaddr-12'h20;
	end
	else if (current_state == READ_STREAM && ss_tvalid)begin
		data_A = (counter%11)*4;
	end
	else if (current_state == CAL && cal_counter <'d11)begin
		data_A = loca%11*'d4;
	end
	else begin
		data_A =0;
	end

end
/////////////////////data
always@(*)begin
	if(current_state == READ_COEF && awvalid && wvalid)begin
		data_Di = 0;
	end
	else if (current_state == READ_STREAM && ss_tvalid)begin
		data_Di = ss_tdata;
	end
	else begin
		data_Di =0;
	end

end

always@(*)begin
	if(current_state == READ_STREAM && ss_tvalid)begin
		ss_tready =1;
	end
	else begin
		ss_tready =0;
	end
end


always @(posedge axis_clk  )begin
	if(!axis_rst_n)begin
		cal_counter <= 0;
	end
	else if(cal_counter == 'd12  )begin
		cal_counter <= 0;
	end
	else if(current_state == CAL  ) begin
		cal_counter <= cal_counter+1;
	end
	

end

always@(posedge axis_clk  )begin
	if(!axis_rst_n)begin
		total_data <= 0;
	end
	else if(cal_counter>0 && cal_counter<'d12)begin
	
		total_data <=total_data+data_Do*tap_Do;
	end
	else if(current_state ==READ_STREAM || current_state ==IDLE)begin
		total_data<=0;
	end


end
//sm_tdata

always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		sm_tdata <= 0;
		sm_tvalid<= 0;
	end
	else if(cal_counter=='d12 && counter<601)begin
	
		sm_tdata  <= total_data;
		sm_tvalid <= 1;
	end
	else begin
		sm_tdata  <= 0;
		sm_tvalid <= 0;
	end

end
always@(posedge axis_clk )begin
	if(!axis_rst_n)begin
		sm_tlast<=0; 
	end
	else if(counter=='d600 &&cal_counter=='d12 )begin
	
		sm_tlast  <= 1;

	end
	else begin
		sm_tlast  <=0;

	end

end


endmodule