/*
 * PCS Transmit Ordered Set State Machine
 * IEEE 802.3-2022 Clause 36 Implementation - Figure 36-5
 * 
 * This module implements the PCS transmit ordered set state machine as specified
 * in Figure 36-5 of IEEE 802.3-2022. It generates the appropriate ordered sets
 * (/C/, /I/, /S/, /T/, /R/, /V/, /D/, /LI/) based on the current state and input conditions.
 *
 */

import pcs_pkg::*;  // Package containing type definitions

module pcs_tx_ordered_set
(
    // Clock and Reset
    input  logic         clk,
    input  logic         rst_n,
    
    // Power-on and Management Reset
    input  logic         power_on,
    input  logic         mr_main_reset,
    
    // Auto-Negotiation Interface
    input  xmit_type_t   xmit,           // CONFIGURATION, IDLE, or DATA from auto-neg
    input  logic         xmitCHANGE,     // xmit variable change detection
    
    // GMII Interface Signals
    input  logic         TX_EN,
    input  logic         TX_ER,
    input  logic [7:0]   TXD,
    
    // Timing and Control Signals
    input  logic         TX_OSET_indicate, // Ordered set timing indication
    input  logic         tx_even,          // Even/odd code group alignment
    input  logic         receiving,        // Collision detection input
    
    // EEE Support
    input  logic         assert_lpidle,    // Low Power Idle assertion
    
    // Output Interface
    output ordered_set_t tx_o_set,         // Output ordered set
    output logic         transmitting,     // Transmission status
    output logic         COL,             // Collision output
    
    // Status and Debug
    output tx_ordered_set_state_t current_state,
    output logic         state_change     // State transition indicator
);
	// State Registers
	tx_ordered_set_state_t state, next_state;
	logic state_change_reg;
	
	// Output Registers  
	ordered_set_t tx_o_set_reg;
	logic transmitting_reg;
	logic COL_reg;

	always_ff @(posedge clk or negedge rst_n) 
	begin
		if (!rst_n) 
		begin
			state <= TX_TEST_XMIT;
			state_change_reg <= 1'b0;
		end 
		else 
		begin
			state_change_reg <= (state != next_state);
			state <= next_state;
		end
	end
	
	// Global reset/initialization condition
	logic global_reset_condition;
	assign global_reset_condition = power_on || mr_main_reset || (xmitCHANGE && TX_OSET_indicate && !tx_even);
	
	// Next State Logic
	always_comb 
	begin
		if (global_reset_condition) 
		begin
			next_state = TX_TEST_XMIT;
		end 
		else 
		begin
			// Default: stay in current state
			next_state = state;
			
			case (state)
				TX_TEST_XMIT: 		begin
										if (xmit == XMIT_CONFIGURATION)
											next_state = CONFIGURATION;
										else if (xmit == XMIT_IDLE || (xmit == XMIT_DATA && (TX_EN || TX_ER)))
											next_state = IDLE;
										else if (xmit == XMIT_DATA && !TX_EN && !TX_ER)
											next_state = XMIT_DATA;
									end

				CONFIGURATION: 		begin
										// Stay in CONFIGURATION until xmitCHANGE
									end

				IDLE: 				begin
										if (xmit == XMIT_DATA && TX_OSET_indicate && !TX_EN && !TX_ER)
											next_state = XMIT_DATA;
									end

				XMIT_DATA: 			begin
										if (TX_EN && !TX_ER && TX_OSET_indicate)
											next_state = START_OF_PACKET;
										else if (TX_EN && TX_ER)
											next_state = ALIGN_ERR_START;
										else if (!assert_lpidle && !TX_EN && TX_OSET_indicate)
											next_state = XMIT_DATA;
										else if (assert_lpidle && TX_OSET_indicate)
											next_state = XMIT_LPIDLE;  // EEE Transition B
									end

				ALIGN_ERR_START: 	begin
										if (TX_OSET_indicate)
											next_state = START_ERROR;
									end

				START_ERROR: 		begin
										if (TX_OSET_indicate)
											next_state = TX_DATA_ERROR;
									end

				TX_DATA_ERROR: 		begin
										if (TX_OSET_indicate)
											next_state = TX_PACKET;
									end

				START_OF_PACKET: 	begin
										if (TX_OSET_indicate)
											next_state = TX_PACKET;
									end

				TX_PACKET: 			begin
										if (TX_EN)
											next_state = TX_DATA;
										else if (!TX_EN && !TX_ER)
											next_state = END_OF_PACKET_NOEXT;
										else if (!TX_EN && TX_ER)
											next_state = END_OF_PACKET_EXT;
									end

				TX_DATA: 			begin
										if (TX_OSET_indicate)
											next_state = TX_PACKET;
									end

				END_OF_PACKET_NOEXT: 	begin
											if (TX_OSET_indicate)
												next_state = EPD2_NOEXT;
										end

				EPD2_NOEXT: 		begin
										if (!tx_even && TX_OSET_indicate)
											next_state = XMIT_DATA;
										else if (tx_even && TX_OSET_indicate)
											next_state = EPD3;
									end

				EPD3: 				begin
										if (TX_OSET_indicate)
											next_state = XMIT_DATA;
									end

				END_OF_PACKET_EXT: 	begin
										if (!TX_ER && TX_OSET_indicate)
											next_state = EXTEND_BY_1;
										else if (TX_ER && TX_OSET_indicate)
											next_state = CARRIER_EXTEND;
									end

				EXTEND_BY_1: 		begin
										if (TX_OSET_indicate)
											next_state = EPD2_NOEXT;
									end

				CARRIER_EXTEND: 	begin
										if (!TX_EN && !TX_ER && TX_OSET_indicate)
											next_state = EXTEND_BY_1;
										else if (TX_EN && TX_ER && TX_OSET_indicate)
											next_state = START_ERROR;
										else if (TX_EN && !TX_ER && TX_OSET_indicate)
											next_state = START_OF_PACKET;
										// else if (!TX_EN && TX_ER && TX_OSET_indicate) // implicit
										//	next_state = CARRIER_EXTEND;
									end

				XMIT_LPIDLE: 		begin
										if (!assert_lpidle && TX_OSET_indicate)
											next_state = XMIT_DATA;  // EEE Transition C
										// else if (assert_lpidle && TX_OSET_indicate) // implicit
										//	next_state = XMIT_LPIDLE;
									end
			
				default: 			begin
										next_state = TX_TEST_XMIT;  // fallback
									end
			endcase
		end
	end
	
	// Output Logic - Implements IEEE 802.3 outputs for each state
	always_comb 
	begin
		// Default outputs
		tx_o_set_reg = OS_I;
		transmitting_reg = transmitting;
		COL_reg = 1'b0;
		
		case (state)
			TX_TEST_XMIT: 		begin
								transmitting_reg = 1'b0;
									COL_reg = 1'b0;
									tx_o_set_reg = OS_I;  // Default idle
								end
		
			CONFIGURATION: 		begin
								// Not transmitting during configuration
								transmitting_reg = 1'b0;
									tx_o_set_reg = OS_C;  // /C/ ordered set
								end
		
			IDLE: 				begin
								// Not transmitting while idle
								transmitting_reg = 1'b0;
									tx_o_set_reg = OS_I;  // /I/ ordered set
								end
		
			XMIT_DATA: 			begin
								// Not transmitting yet
								transmitting_reg = 1'b0;
									tx_o_set_reg = OS_I;  // /I/ ordered set
								end
		
			START_ERROR: 		begin
									transmitting_reg = 1'b1;
									COL_reg = receiving;
									tx_o_set_reg = OS_S;  // /S/ ordered set (Start of Packet)
								end
		
			TX_DATA_ERROR: 		begin
									COL_reg = receiving;
									tx_o_set_reg = OS_V;  // /V/ ordered set (Error propagation)
								end
		
			START_OF_PACKET: 	begin
									transmitting_reg = 1'b1;
									COL_reg = receiving;
									tx_o_set_reg = OS_S;  // /S/ ordered set
								end
		
			TX_DATA: 			begin
									COL_reg = receiving;
									tx_o_set_reg = OS_D;  // /D/ ordered set (will be processed by VOID() function in code-group SM)
								end
		
			END_OF_PACKET_NOEXT: 	begin
									COL_reg = 1'b0;
									tx_o_set_reg = OS_T;  // /T/ ordered set
									if (!tx_even)
										transmitting_reg = 1'b0;
									end
		
			EPD2_NOEXT: 		begin
									tx_o_set_reg = OS_R;  // /R/ ordered set
								end
		
			EPD3: 				begin
									tx_o_set_reg = OS_R;  // /R/ ordered set
								end
		
			END_OF_PACKET_EXT: 	begin
									COL_reg = receiving;
									tx_o_set_reg = OS_T;  // /T/ ordered set (will be processed by VOID() function in code-group SM)
								end
		
			EXTEND_BY_1: 		begin
								COL_reg = 1'b0;
								tx_o_set_reg = OS_R;  // /R/ ordered set
								if (!tx_even)
									transmitting_reg = 1'b0;
								end
		
			CARRIER_EXTEND: 	begin
									COL_reg = receiving;
									tx_o_set_reg = OS_R;  // /R/ ordered set (will be processed by VOID() function in code-group SM)
								end
		
			XMIT_LPIDLE: 		begin
									tx_o_set_reg = OS_LI;  // /LI/ ordered set (Low Power Idle)
								end
		
			default: 			begin
									tx_o_set_reg = OS_I;
									transmitting_reg = 1'b0;
									COL_reg = 1'b0;
								end
		endcase
	end
	
	// Register outputs
	always_ff @(posedge clk or negedge rst_n) 
	begin
		if (!rst_n) 
		begin
			tx_o_set <= OS_I;
			transmitting <= 1'b0;
			COL <= 1'b0;
		end 
		else 
		begin
			tx_o_set <= tx_o_set_reg;
			transmitting <= transmitting_reg;
			COL <= COL_reg;
		end
	end
	
	// Debug and status outputs
	assign current_state = state;
	assign state_change = state_change_reg;
endmodule