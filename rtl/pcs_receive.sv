/*
 * PCS Transmit Path Module
 * IEEE 802.3-2022 Clause 36 PCS Receive State Machine
 * 
 * This module implements the PCS receive state machine as specified in Figures 36-7a, 7b and 7c.
 */

import pcs_pkg::*;

module pcs_receive (
    // Clock and Reset
    input  logic        clk,
    input  logic        rst_n,
    
    // From Synchronization Module  
    input  logic [9:0]  rx_aligned_cg,
    input  logic        code_group_valid,
    input  logic        rx_even,
    
    // Control Inputs
    input  logic        power_on,
    input  logic        mr_main_reset,
    input  sync_status_t sync_status,
    input  xmit_type_t  xmit,
    input  signal_detect_t signal_detect,
    input  sync_status_t code_sync_status,
    
    // GMII Outputs
    output logic [7:0]  GMII_RXD,
    output logic        GMII_RX_DV,
    output logic        GMII_RX_ER,
    
    // Configuration Interface
    output logic [15:0] rx_Config_Reg,
    
    // Status Outputs
    output logic        receiving,
    output logic        rx_lpi_active,
    output logic        rx_quiet,
    output logic [3:0]  wake_error_counter,
    
    // To Auto-Negotiation (RUDI messages)
    output logic        rudi_invalid,
    output logic        rudi_c,
    output logic        rudi_i
);

    // State Machine states
    rx_state_t current_state, next_state;
    
    // SUDI Interpretation (Clause 36.2.5.1.6)
    logic [9:0] current_cg;
    logic       sudi;
    
    assign current_cg = rx_aligned_cg;  // [/x/] parameter
    assign sudi = code_group_valid;      // SUDI event
    // rx_even input is the EVEN/ODD parameter
    
    // Code-Group Detection Signals
    logic       is_k28_5, is_d21_5, is_d2_2, is_d6_5, is_d26_4, is_d5_6, is_d16_2;
    logic       is_s, is_t, is_r, is_d0_0;
    logic       is_d_group;
    logic [7:0] decoded_data;
    logic       is_control_char;
    logic       decode_error;
    logic       decoder_disparity;
    
	// Delayed data/control flags aligned with prev_cg_1 and prev_cg_2
    logic       is_data_current;
    logic       prev_is_data_1, prev_is_data_2;
	
	// Timer control outputs
    logic start_tq_reg, start_tw_reg, start_wf_reg;
    
    // 8B/10B Decoder
    decoder_8b10b u_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .enable(sudi),
        .code_group_in(current_cg),
        .data_out(decoded_data),
        .is_control_out(is_control_char),
        .disparity_out(decoder_disparity),
        .decode_error(decode_error)
    );
    
    // Specific code-group detection
    // Table 36-2: Special Code-Groups
    assign is_k28_5 = (current_cg == K28_5_RD_NEG) || (current_cg == K28_5_RD_POS); // Comma
    assign is_s     = (current_cg == K27_7_RD_NEG) || (current_cg == K27_7_RD_POS); // SPD /S/
    assign is_t     = (current_cg == K29_7_RD_NEG) || (current_cg == K29_7_RD_POS); // EPD /T/
    assign is_r     = (current_cg == K23_7_RD_NEG) || (current_cg == K23_7_RD_POS); // /R/
    
    // Specific data code-groups (need to check both RD- and RD+ where applicable)
    assign is_d21_5 = (current_cg == D21_5);
    assign is_d2_2  = (current_cg == D2_2_RD_NEG) || (current_cg == D2_2_RD_POS);
    assign is_d6_5  = (current_cg == D6_5);
    assign is_d26_4 = (current_cg == D26_4_RD_NEG) || (current_cg == D26_4_RD_POS);
    assign is_d5_6  = (current_cg == D5_6);
    assign is_d16_2 = (current_cg == D16_2);
    assign is_d0_0  = (current_cg == D0_0);
    
    // General data group detection (any valid /D/ code)
    assign is_data_current = !is_control_char && !decode_error;
    assign is_d_group = is_data_current;

    // Internal functions per Clause 36.2.5.1.3 and 36.2.5.1.4
    // idle_d: SUDI of data and not one of D21.5, D2.2, D6.5, D26.4
    logic idle_d;
    assign idle_d = sudi && is_data_current && !is_d21_5 && !is_d2_2 && !is_d6_5 && !is_d26_4;

    // carrier_detect: on EVEN boundaries, detect non-K28.5-like groups per bit difference rules
    logic carrier_detect;
    logic [9:0] expected_k28_5;
    logic [3:0] bit_diff_from_expected, bit_diff_from_rd_neg, bit_diff_from_rd_pos;

    function automatic logic [3:0] count_ones10(input logic [9:0] v);
        count_ones10 = v[0]+v[1]+v[2]+v[3]+v[4]+v[5]+v[6]+v[7]+v[8]+v[9];
    endfunction

    assign expected_k28_5 = (decoder_disparity == NEGATIVE) ? K28_5_RD_NEG : K28_5_RD_POS;
    assign bit_diff_from_expected = count_ones10(current_cg ^ expected_k28_5);
    assign bit_diff_from_rd_neg   = count_ones10(current_cg ^ K28_5_RD_NEG);
    assign bit_diff_from_rd_pos   = count_ones10(current_cg ^ K28_5_RD_POS);
    assign carrier_detect = rx_even && ((bit_diff_from_rd_neg >= 4'd2 && bit_diff_from_rd_pos >= 4'd2) ||
                                        (bit_diff_from_expected >= 4'd2 && bit_diff_from_expected <= 4'd9));
    
    // check_end Function (Clause 36.2.5.1.4)
    logic [9:0] prev_cg_1, prev_cg_2;
    check_end_t check_end;
    
    always_ff @(posedge clk or negedge rst_n) 
	begin
        if (!rst_n) 
		begin
            prev_cg_1 <= 10'h0;
            prev_cg_2 <= 10'h0;
            prev_is_data_1 <= 1'b0;
            prev_is_data_2 <= 1'b0;
        end 
		else if (sudi) 
		begin
            prev_cg_2 <= prev_cg_1;
            prev_cg_1 <= current_cg;
            prev_is_data_2 <= prev_is_data_1;
            prev_is_data_1 <= is_data_current;
        end
    end
    
    // check_end patterns (current + next 2 code-groups)
    always_comb 
	begin
        check_end = CHECK_END_NONE;
        
        // /T/R/K28.5/ pattern
        if ((prev_cg_2 == K29_7_RD_NEG || prev_cg_2 == K29_7_RD_POS) &&
            (prev_cg_1 == K23_7_RD_NEG || prev_cg_1 == K23_7_RD_POS) &&
            (current_cg == K28_5_RD_NEG || current_cg == K28_5_RD_POS))
            check_end = CHECK_END_TRK;
            
        // /T/R/R/ pattern
        else if ((prev_cg_2 == K29_7_RD_NEG || prev_cg_2 == K29_7_RD_POS) &&
                 (prev_cg_1 == K23_7_RD_NEG || prev_cg_1 == K23_7_RD_POS) &&
                 (current_cg == K23_7_RD_NEG || current_cg == K23_7_RD_POS))
            check_end = CHECK_END_TRR;
            
        // /R/R/R/ pattern
        else if ((prev_cg_2 == K23_7_RD_NEG || prev_cg_2 == K23_7_RD_POS) &&
                 (prev_cg_1 == K23_7_RD_NEG || prev_cg_1 == K23_7_RD_POS) &&
                 (current_cg == K23_7_RD_NEG || current_cg == K23_7_RD_POS))
            check_end = CHECK_END_RRR;
            
        // /R/R/S/ pattern
        else if ((prev_cg_2 == K23_7_RD_NEG || prev_cg_2 == K23_7_RD_POS) &&
                 (prev_cg_1 == K23_7_RD_NEG || prev_cg_1 == K23_7_RD_POS) &&
                 (current_cg == K27_7_RD_NEG || current_cg == K27_7_RD_POS))
            check_end = CHECK_END_RRS;
            
        // /K28.5/D/K28.5/ pattern (early end)
        else if ((prev_cg_2 == K28_5_RD_NEG || prev_cg_2 == K28_5_RD_POS) &&
                 prev_is_data_1 && // prev_cg_1 was data
                 (current_cg == K28_5_RD_NEG || current_cg == K28_5_RD_POS))
            check_end = CHECK_END_K_D_K;
            
        // /K28.5/(D21.5 + D2.2)/D0.0/ pattern (early end)
        else if ((prev_cg_2 == K28_5_RD_NEG || prev_cg_2 == K28_5_RD_POS) &&
                 (prev_cg_1 == D21_5 || prev_cg_1 == D2_2_RD_NEG || prev_cg_1 == D2_2_RD_POS) &&
                 (current_cg == D0_0))
            check_end = CHECK_END_K_C_D;
    end
    
    // Internal Timer Signals
    logic rx_tq_timer_done;
    logic rx_tw_timer_done;
    logic rx_wf_timer_done;
    logic start_rx_tq_timer;
    logic start_rx_tw_timer;
    logic start_rx_wf_timer;
    
    // Timer Instances
    timer_module #(
        .TIMER_VALUE(TQ_TIMER_VALUE),
        .COUNTER_WIDTH(16)
    ) rx_tq_timer_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_rx_tq_timer),
        .done(rx_tq_timer_done)
    );
    
    timer_module #(
        .TIMER_VALUE(TW_TIMER_VALUE),
        .COUNTER_WIDTH(16)
    ) rx_tw_timer_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_rx_tw_timer),
        .done(rx_tw_timer_done)
    );
    
    timer_module #(
        .TIMER_VALUE(WF_TIMER_VALUE),
        .COUNTER_WIDTH(32)
    ) rx_wf_timer_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_rx_wf_timer),
        .done(rx_wf_timer_done)
    );
    
    // State Register
    always_ff @(posedge clk or negedge rst_n) 
	begin
        if (!rst_n)
            current_state <= RX_LINK_FAILED;
        else
            current_state <= next_state;
    end
    
    // next_state logic (implemented from figure 36-7a, 36-7b and 36-7c)
    always_comb 
	begin
        next_state = current_state;
        
        // Global conditions
        if (power_on || mr_main_reset) 
		begin
            next_state = RX_WAIT_FOR_K;
        end
        else if (sync_status == SYNC_FAIL && sudi) 
		begin
            next_state = RX_LINK_FAILED;
        end
        else 
		begin
            case (current_state)
                RX_LINK_FAILED: 	begin
										if (sudi)
											next_state = RX_WAIT_FOR_K;
									end

                RX_WAIT_FOR_K: 		begin
										if (sudi && is_k28_5 && rx_even)
											next_state = RX_K;
									end


                RX_K: 				begin
										if (sudi && (is_d21_5 || is_d2_2))
											next_state = RX_CB;
										else if (sudi && !is_d_group && xmit != XMIT_DATA)
											next_state = RX_INVALID;
										else if (xmit == XMIT_DATA && sudi && (is_d6_5 || is_d26_4))
											next_state = RX_SLEEP;
										else if ((xmit != XMIT_DATA && sudi && is_d_group && !is_d21_5 && !is_d2_2) ||
												 (xmit == XMIT_DATA && idle_d))
											next_state = RX_IDLE_D;
									end

                RX_CB: 				begin
										if (sudi && is_d_group)
											next_state = RX_CC;
										else if (sudi && !is_d_group)
											next_state = RX_INVALID;
									end

                RX_CC: 				begin
										if (sudi && is_d_group)
											next_state = RX_CD;
										else if (sudi && !is_d_group)
											next_state = RX_INVALID;
									end

                RX_CD: 				begin
										if (sudi && is_k28_5 && rx_even)
											next_state = RX_K;
										else if (sudi && (!is_k28_5 || !rx_even))
											next_state = RX_INVALID;
									end

                RX_IDLE_D: 			begin
										if (sudi && !is_k28_5 && xmit != XMIT_DATA)
											next_state = RX_INVALID;
										else if (sudi && xmit == XMIT_DATA && carrier_detect)
											next_state = RX_CARRIER_DETECT;
										else if ((sudi && xmit == XMIT_DATA && !carrier_detect) || (sudi && is_k28_5))
											next_state = RX_K;
									end

                RX_CARRIER_DETECT: 	begin
										if (!is_s)
											next_state = RX_FALSE_CARRIER;
										else if (is_s)
											next_state = RX_START_OF_PACKET;
									end

                RX_FALSE_CARRIER: 	begin
										if (sudi && is_k28_5 && rx_even)
											next_state = RX_K;
									end

                RX_INVALID: 		begin
										if (sudi && is_k28_5 && rx_even)
											next_state = RX_K;
										else if (sudi && !is_k28_5 && rx_even)
											next_state = RX_WAIT_FOR_K;
									end

                RX_START_OF_PACKET: begin
										if (sudi)
											next_state = RX_RECEIVE;
									end

                RX_RECEIVE: 		begin
										if ((check_end == CHECK_END_K_D_K || check_end == CHECK_END_K_C_D) && rx_even)
											next_state = RX_EARLY_END;
										else if (rx_even && check_end == CHECK_END_TRK)
											next_state = RX_TRI_RRI;
										else if (check_end == CHECK_END_TRR)
											next_state = RX_TRR_EXTEND;
										else if (check_end == CHECK_END_RRR)
											next_state = RX_EARLY_END_EXT;
										else if (is_d_group)
											next_state = RX_DATA;
										else
											next_state = RX_DATA_ERROR;
									end

                RX_EARLY_END: 		begin
										if (sudi && !is_d21_5 && !is_d2_2)
											next_state = RX_IDLE_D;
										else if (sudi && (is_d21_5 || is_d2_2))
											next_state = RX_CB;
									end

                RX_TRI_RRI: 		begin
										if (sudi && is_k28_5)
											next_state = RX_K;
									end

                RX_TRR_EXTEND: 		begin
										if (sudi)
											next_state = RX_EPD2_CHECK_END;
									end

                RX_EARLY_END_EXT: 	begin
										if (sudi)
											next_state = RX_EPD2_CHECK_END;
									end

                RX_DATA: 			begin
										if (sudi)
											next_state = RX_RECEIVE;
									end

                RX_DATA_ERROR: 		begin
										if (sudi)
											next_state = RX_RECEIVE;
									end

                RX_EPD2_CHECK_END: 	begin
										if (check_end == CHECK_END_RRR)
											next_state = RX_TRR_EXTEND;
										else if (check_end == CHECK_END_TRK && rx_even)
											next_state = RX_TRI_RRI;
										else if (check_end == CHECK_END_RRS)
											next_state = RX_PACKET_BURST_RRS;
										else
											next_state = RX_EXTEND_ERR;
									end

                RX_PACKET_BURST_RRS: 	begin
											if (sudi && is_s)
												next_state = RX_START_OF_PACKET;
										end

                RX_EXTEND_ERR: 		begin
										if (sudi && is_s)
											next_state = RX_START_OF_PACKET;
										else if (sudi && is_k28_5 && rx_even)
											next_state = RX_K;
										else if (sudi && !is_s && !(is_k28_5 && rx_even))
											next_state = RX_EPD2_CHECK_END;
									end

                // EEE STATES
                RX_SLEEP: 			begin
										// Un-conditional Transition
										next_state = RX_START_TQ_TIMER;
									end

                RX_START_TQ_TIMER: 	begin
										// Un-conditional Transition
										next_state = RX_LP_IDLE_D;
									end

                RX_LP_IDLE_D: 		begin
										if (signal_detect == SIGNAL_OK && rx_tq_timer_done)
											next_state = RX_LINK_FAIL;
										else if (signal_detect == SIGNAL_OK && !rx_tq_timer_done && 
												 xmit != XMIT_DATA && sudi && !is_k28_5)
											next_state = RX_INVALID;
										else if (signal_detect == SIGNAL_FAIL)
											next_state = RX_QUIET;
										else if (signal_detect == SIGNAL_OK && !rx_tq_timer_done && 
												 ((xmit == XMIT_DATA && sudi) || (sudi && !is_k28_5)))
											next_state = RX_LPI_K;
									end

                RX_LPI_K: 			begin
										if (signal_detect == SIGNAL_FAIL)
											next_state = RX_QUIET;
										else if (signal_detect == SIGNAL_OK && sudi && (is_d21_5 || is_d2_2))
											next_state = RX_CB;
										else if (signal_detect == SIGNAL_OK && xmit != XMIT_DATA && 
												 sudi && !is_d_group)
											next_state = RX_INVALID;
										else if (signal_detect == SIGNAL_OK && sudi && (is_d5_6 || is_d16_2))
											next_state = RX_IDLE_D;
										else if (signal_detect == SIGNAL_OK && xmit == XMIT_DATA && 
												 sudi && (is_d6_5 || is_d26_4))
											next_state = RX_START_TQ_TIMER;
										else if (signal_detect == SIGNAL_OK && 
												 ((xmit != XMIT_DATA && sudi && is_d_group && !is_d21_5 && !is_d2_2 && !is_d5_6 && !is_d16_2) ||
												  (xmit == XMIT_DATA && sudi && !is_d21_5 && !is_d2_2 && !is_d5_6 && !is_d16_2 && !is_d6_5 && !is_d26_4)))
											next_state = RX_LP_IDLE_D;
									end

                RX_QUIET: 			begin
										if (signal_detect == SIGNAL_FAIL && rx_tq_timer_done)
											next_state = RX_LINK_FAIL;
										else if (signal_detect == SIGNAL_OK)
											next_state = RX_WAKE;
									end

                RX_WAKE: 			begin
										if (signal_detect == SIGNAL_OK && rx_tw_timer_done)
											next_state = RX_WTF;
										else if (signal_detect == SIGNAL_OK && !rx_tw_timer_done && 
												 code_sync_status == SYNC_OK && sudi && is_k28_5 && rx_even)
											next_state = RX_WAKE_DONE;
										else if (signal_detect == SIGNAL_FAIL)
											next_state = RX_QUIET;
									end

                RX_WTF: 			begin
										if (signal_detect == SIGNAL_OK && rx_wf_timer_done)
											next_state = RX_LINK_FAIL;
										else if (signal_detect == SIGNAL_OK && !rx_wf_timer_done && 
												 code_sync_status == SYNC_OK && sudi && is_k28_5 && rx_even)
											next_state = RX_WAKE_DONE;
										else if (signal_detect == SIGNAL_FAIL)
											next_state = RX_QUIET;
									end

                RX_LINK_FAIL: 		begin
										if (sudi)
											next_state = RX_LINK_FAILED;
									end

                RX_WAKE_DONE: 		begin
										// Un-conditional Transition
										next_state = RX_LPI_K;
									end

                default: 			next_state = RX_LINK_FAILED;
            endcase
        end
    end
    
    // output logic (implemented from figure 36-7a, 36-7b and 36-7c)
    
    always_ff @(posedge clk or negedge rst_n) 
	begin
        if (!rst_n) 
		begin
            GMII_RXD 		<= 8'h00;
            GMII_RX_DV 		<= 1'b0;
            GMII_RX_ER 		<= 1'b0;
            receiving 		<= 1'b0;
            rx_Config_Reg 	<= 16'h0000;
            rudi_invalid 	<= 1'b0;
            rudi_c		 	<= 1'b0;
            rudi_i 			<= 1'b0;
            rx_lpi_active 	<= 1'b0;
            rx_quiet 		<= 1'b0;
            wake_error_counter <= 4'h0;
            start_tq_reg 	<= 1'b0;
            start_tw_reg 	<= 1'b0;
            start_wf_reg 	<= 1'b0;
        end 
		else 
		begin
            // Default values
            rudi_invalid 	<= 1'b0;
            rudi_c 			<= 1'b0;
            rudi_i 			<= 1'b0;
            start_tq_reg 	<= 1'b0;
            start_tw_reg 	<= 1'b0;
            start_wf_reg 	<= 1'b0;
            
            case (current_state)
                RX_LINK_FAILED: 	begin
										rx_lpi_active <= 1'b0;
										// RUDI(INVALID) only for non-data mode
										if (xmit != XMIT_DATA)
											rudi_invalid <= 1'b1;
										if (receiving) 
										begin
											receiving 	<= 1'b0;
											GMII_RX_ER 	<= 1'b1;
											GMII_RX_DV 	<= 1'b0;
										end 
										else 
										begin
											receiving 	<= 1'b0;
											GMII_RX_DV 	<= 1'b0;
											GMII_RX_ER 	<= 1'b0;
										end
									end
                
                RX_WAIT_FOR_K:		begin
										receiving 	<= 1'b0;
										GMII_RX_DV 	<= 1'b0;
										GMII_RX_ER 	<= 1'b0;
									end
                
                RX_K: 				begin
										receiving 	<= 1'b0;
										GMII_RX_DV 	<= 1'b0;
										GMII_RX_ER 	<= 1'b0;
									end
                
                RX_CB: 				begin
										receiving 	<= 1'b0;
										GMII_RX_DV 	<= 1'b0;
										GMII_RX_ER 	<= 1'b0;
										rx_lpi_active <= 1'b0;
									end
                
                RX_CC: 				begin
										if (sudi)
											rx_Config_Reg[7:0] <= decoded_data;
									end
                
                RX_CD: 				begin
										if (sudi) begin
											rx_Config_Reg[15:8] <= decoded_data;
											// RUDI(/C/) asserted when complete /C/ ordered set received (K28.5 termination)
											if (is_k28_5 && rx_even)
												rudi_c <= 1'b1;
										end
									end
                
                RX_IDLE_D: 			begin
										receiving 	<= 1'b0;
										GMII_RX_DV 	<= 1'b0;
										GMII_RX_ER 	<= 1'b0;
										rx_lpi_active <= 1'b0;
										// RUDI(/I/) asserted when idle data code-group is received
										if (sudi && is_d_group)
											rudi_i <= 1'b1;
									end
                
                RX_CARRIER_DETECT: 	begin
										receiving <= 1'b1;
									end
                
                RX_FALSE_CARRIER: 	begin
										GMII_RX_ER 	<= 1'b1;
										GMII_RXD 	<= 8'h0E;
									end
                
                RX_INVALID: 		begin
										// RUDI(INVALID) only for configuration mode errors
										if (xmit == XMIT_CONFIGURATION)
											rudi_invalid <= 1'b1;
										if (xmit == XMIT_DATA) begin
											receiving <= 1'b1;
											rx_lpi_active <= 1'b0;
										end
									end
                
                RX_START_OF_PACKET: begin
										GMII_RX_DV 	<= 1'b1;
										GMII_RX_ER 	<= 1'b0;
										GMII_RXD 	<= 8'h55;
									end
                
                RX_DATA: 			begin
										GMII_RX_ER 	<= 1'b0;
										GMII_RXD 	<= decoded_data;
									end
                
                RX_DATA_ERROR: 		begin
										GMII_RX_ER 	<= 1'b1;
										GMII_RXD 	<= decoded_data;  // Must output data alongwith the error flag
									end
                
                RX_EARLY_END: 		begin
										GMII_RX_ER <= 1'b1;
									end
                
                RX_TRI_RRI: 		begin
										receiving 	<= 1'b0;
										GMII_RX_DV 	<= 1'b0;
										GMII_RX_ER 	<= 1'b0;
									end
                
                RX_TRR_EXTEND: 		begin
										GMII_RX_DV 	<= 1'b0;
										GMII_RX_ER 	<= 1'b1;
										GMII_RXD 	<= 8'h0F;
									end
                
                RX_EARLY_END_EXT: 	begin
										GMII_RX_ER <= 1'b1;
									end
                
                RX_EPD2_CHECK_END: 	begin
										// No outputs asserted
									end
                
                RX_PACKET_BURST_RRS: 	begin
											GMII_RX_DV 	<= 1'b0;
											GMII_RXD 	<= 8'h0F;
										end
                
                RX_EXTEND_ERR: 		begin
										GMII_RX_DV 	<= 1'b0;
										GMII_RXD 	<= 8'h1F;
									end
                
                RX_SLEEP: 			begin
										rx_lpi_active 	<= 1'b1;
										receiving 		<= 1'b0;
										GMII_RX_DV 		<= 1'b0;
										GMII_RX_ER 		<= 1'b1;
										GMII_RXD 		<= 8'h01;
									end
                
                RX_START_TQ_TIMER: 	begin
										start_tq_reg <= 1'b1;
									end
                
                RX_QUIET: 			begin
										rx_quiet <= 1'b1;
									end
                
                RX_WAKE: 			begin
										rx_quiet 		<= 1'b0;
										start_tw_reg 	<= 1'b1;
									end
                
                RX_WTF: 			begin
										wake_error_counter 	<= wake_error_counter + 4'h1;
										start_wf_reg 		<= 1'b1;
									end
                
                RX_LINK_FAIL: 		begin
										rx_quiet 		<= 1'b0;
										rx_lpi_active 	<= 1'b0;
									end
                
                RX_LPI_K: 			begin
										// No outputs asserted
									end
                
                RX_WAKE_DONE: 		begin
										start_tq_reg <= 1'b1;
									end
            endcase
        end
    end
endmodule