/*
 * PCS Transmit Code-Group State Machine
 * IEEE 802.3-2022 Clause 36 Implementation - Figure 36-6
 * 
 * This module implements the PCS transmit code-group state machine as specified
 * in Figure 36-6 of IEEE 802.3-2022. It generates 10-bit code groups based on 
 * ordered sets from the transmit ordered set process.
 */

import pcs_pkg::*;

module pcs_tx_code_group
(
    // Clock and Reset
    input  logic         clk,
    input  logic         rst_n,
    
    // Power-on and Management Reset  
    input  logic         power_on,
    input  logic         mr_main_reset,
    
    // Interface with Ordered Set State Machine
    input  ordered_set_t tx_o_set,          // From ordered set SM
    output logic         TX_OSET_indicate,  // Back to ordered set SM
    
    // Auto-Negotiation Interface
    input  logic [15:0]  tx_Config_Reg,     // Configuration register
    
    // GMII Data Interface
    input  logic [7:0]   TXD,               // GMII transmit data
    
    // Timer Interface
    input  logic         cg_timer_done,     // Code group timer
    
    // Output Interface  
    output logic [9:0]   tx_code_group,     // 10-bit code group output
    output logic         tx_even,           // Even/odd alignment
    output disparity_t   tx_disparity,      // Running disparity
    
    // Status and Debug
    output tx_code_group_state_t current_state,
    output logic         state_change
);

    // State Registers
    tx_code_group_state_t state, next_state;
    logic state_change_reg;
    
    // Internal Registers
    logic [9:0]   tx_code_group_reg;
    logic         tx_even_reg;
    disparity_t   tx_disparity_reg;
    logic         TX_OSET_indicate_reg;
    
    // 8B/10B Encoder Interface  
    logic [7:0]   encode_data_in;
    logic         encode_is_control;
    logic         encode_enable;
    logic [9:0]   encode_code_group_out;
    logic         encode_disparity_out;
    logic         encode_error;
    
    // Instantiate 8B/10B Encoder
    encoder_8b10b u_encoder (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (encode_enable),
        .data_in        (encode_data_in),
        .is_control     (encode_is_control),
        .code_group_out (encode_code_group_out),
        .disparity_out  (encode_disparity_out),
        .encode_error   (encode_error)
    );

    // State register logic
    always_ff @(posedge clk or negedge rst_n) 
	begin
        if (!rst_n) 
		begin
            state <= GENERATE_CODE_GROUPS;
            state_change_reg <= 1'b0;
        end 
		else 
		begin
            state_change_reg <= (state != next_state);
            state <= next_state;
        end
    end
    
    // Global reset condition
    logic global_reset_condition;
    assign global_reset_condition = power_on || mr_main_reset;
    
    // Next State Logic
    always_comb 
	begin
        if (global_reset_condition) 
		begin
            next_state = GENERATE_CODE_GROUPS;
        end 
		else 
		begin
            // Default: stay in current state
            next_state = state;
            
            case (state)
                GENERATE_CODE_GROUPS: 	begin
											if (tx_o_set == OS_V || tx_o_set == OS_S || tx_o_set == OS_T || tx_o_set == OS_R)
												next_state = SPECIAL_GO;
											else if (tx_o_set == OS_D)
												next_state = DATA_GO;
											else if (tx_o_set == OS_I || tx_o_set == OS_LI)  
												next_state = IDLE_DISPARITY_TEST;
											else if (tx_o_set == OS_C)
												next_state = CONFIGURATION_C1A;
										end
                
                SPECIAL_GO: 			begin
											if (cg_timer_done)
												next_state = GENERATE_CODE_GROUPS;
										end
                
                // Configuration C1 sequence
                CONFIGURATION_C1A: 		begin
											if (cg_timer_done)
												next_state = CONFIGURATION_C1B;
										end
                
                CONFIGURATION_C1B: 		begin
											if (cg_timer_done)
												next_state = CONFIGURATION_C1C;
										end
                
                CONFIGURATION_C1C: 		begin
											if (cg_timer_done)
												next_state = CONFIGURATION_C1D;
										end
                
                CONFIGURATION_C1D: 		begin
											if (tx_o_set == OS_C && cg_timer_done)
												next_state = CONFIGURATION_C2A;
											else if (tx_o_set != OS_C && cg_timer_done)
												next_state = GENERATE_CODE_GROUPS;
										end
                
                // Configuration C2 sequence  
                CONFIGURATION_C2A: 		begin
											if (cg_timer_done)
												next_state = CONFIGURATION_C2B;
										end
                
                CONFIGURATION_C2B: 		begin
											if (cg_timer_done)
												next_state = CONFIGURATION_C2C;
										end
                
                CONFIGURATION_C2C: 		begin
											if (cg_timer_done)
												next_state = CONFIGURATION_C2D;
										end
                
                CONFIGURATION_C2D: 		begin
											if (cg_timer_done)
												next_state = GENERATE_CODE_GROUPS;
										end

                IDLE_DISPARITY_TEST: 	begin
											if (tx_disparity == POSITIVE)
												next_state = IDLE_DISPARITY_WRONG;
											else if (tx_disparity == NEGATIVE)
												next_state = IDLE_DISPARITY_OK;
										end
                
                IDLE_DISPARITY_WRONG: 	begin
											if (cg_timer_done)
												next_state = IDLE_I1B;
										end

                IDLE_DISPARITY_OK: 		begin
											if (cg_timer_done)
												next_state = IDLE_I2B;
										end

                IDLE_I1B: 				begin
											if (cg_timer_done)
												next_state = GENERATE_CODE_GROUPS;
										end

                IDLE_I2B: 				begin
											if (cg_timer_done)
												next_state = GENERATE_CODE_GROUPS;
										end
                
                DATA_GO: 				begin
											if (cg_timer_done)
												next_state = GENERATE_CODE_GROUPS;
										end

                default: 				begin
											next_state = GENERATE_CODE_GROUPS;
										end
            endcase
        end
    end
    
    // Output Logic
    always_comb 
	begin
        // Default outputs
        tx_code_group_reg    = 10'h000;
        tx_even_reg          = tx_even;      // Maintain current value
        tx_disparity_reg     = tx_disparity; // Maintain current value
        TX_OSET_indicate_reg = 1'b0;
        
        // Encoder inputs default
        encode_data_in    = 8'h00;
        encode_is_control = 1'b0;
        encode_enable     = 1'b0;
        
        case (state)
            GENERATE_CODE_GROUPS: 		begin
											TX_OSET_indicate_reg = 1'b0;
										end
            
            SPECIAL_GO: 				begin
											case (tx_o_set)
												OS_V: tx_code_group_reg = (tx_disparity == NEGATIVE) ? K30_7_RD_NEG : K30_7_RD_POS; // /V/ -> K30.7
												OS_S: tx_code_group_reg = (tx_disparity == NEGATIVE) ? K27_7_RD_NEG : K27_7_RD_POS; // /S/ -> K27.7  
												OS_T: tx_code_group_reg = (tx_disparity == NEGATIVE) ? K29_7_RD_NEG : K29_7_RD_POS; // /T/ -> K29.7
												OS_R: tx_code_group_reg = (tx_disparity == NEGATIVE) ? K23_7_RD_NEG : K23_7_RD_POS; // /R/ -> K23.7
												default: tx_code_group_reg = 10'h000;
											endcase
											tx_even_reg 			= !tx_even;
											tx_disparity_reg 		= tx_disparity; // Maintain current disparity 
											TX_OSET_indicate_reg 	= cg_timer_done;
											encode_enable 			= 1'b0; // No encoding needed
										end
            
            CONFIGURATION_C1A: 			begin
											// K28.5 disparity-dependent  
											if (tx_disparity == NEGATIVE)
												tx_code_group_reg = K28_5_RD_NEG;
											else
												tx_code_group_reg = K28_5_RD_POS;
											tx_even_reg 			= 1'b1;  
											tx_disparity_reg 		= (tx_disparity == NEGATIVE) ? POSITIVE : NEGATIVE;
											TX_OSET_indicate_reg 	= 1'b0;
										end
            
            CONFIGURATION_C1B: 			begin
											tx_code_group_reg = D21_5;   // D21.5 disparity neutral
											tx_even_reg = 1'b0;         // FALSE
											tx_disparity_reg = tx_disparity;
											TX_OSET_indicate_reg = 1'b0;
										end
            
            CONFIGURATION_C1C: 			begin
											encode_enable = 1'b1;
											encode_data_in = tx_Config_Reg[7:0];
											encode_is_control = 1'b0;
											tx_code_group_reg = encode_code_group_out;
											tx_even_reg = 1'b1;
											tx_disparity_reg = encode_disparity_out;
											TX_OSET_indicate_reg = 1'b0;
										end
            
            CONFIGURATION_C1D: 			begin
											encode_enable = 1'b1;
											encode_data_in = tx_Config_Reg[15:8];
											encode_is_control = 1'b0;
											tx_code_group_reg = encode_code_group_out;
											tx_even_reg = 1'b0;
											tx_disparity_reg = encode_disparity_out;
											TX_OSET_indicate_reg = cg_timer_done;
										end
            
            CONFIGURATION_C2A: 			begin
											if (tx_disparity == NEGATIVE)
												tx_code_group_reg = K28_5_RD_NEG;
											else
												tx_code_group_reg = K28_5_RD_POS;
											tx_even_reg = 1'b1;
											tx_disparity_reg = (tx_disparity == NEGATIVE) ? POSITIVE : NEGATIVE;
											TX_OSET_indicate_reg = 1'b0;
										end
            
            CONFIGURATION_C2B: 			begin
											if (tx_disparity == NEGATIVE)
												tx_code_group_reg = D2_2_RD_NEG;
											else
												tx_code_group_reg = D2_2_RD_POS;
											tx_even_reg = 1'b0;
											tx_disparity_reg = (tx_disparity == NEGATIVE) ? POSITIVE : NEGATIVE;
											TX_OSET_indicate_reg = 1'b0;
										end
            
            CONFIGURATION_C2C: 			begin
											encode_enable = 1'b1;
											encode_data_in = tx_Config_Reg[7:0];
											encode_is_control = 1'b0;
											tx_code_group_reg = encode_code_group_out;
											tx_even_reg = 1'b1;
											tx_disparity_reg = encode_disparity_out;
											TX_OSET_indicate_reg = 1'b0;
										end
            
            CONFIGURATION_C2D: 			begin
											encode_enable = 1'b1;
											encode_data_in = tx_Config_Reg[15:8];
											encode_is_control = 1'b0;
											tx_code_group_reg = encode_code_group_out;
											tx_even_reg = 1'b0;
											tx_disparity_reg = encode_disparity_out;
											TX_OSET_indicate_reg = cg_timer_done;
										end
            
            IDLE_DISPARITY_TEST: 		begin
											TX_OSET_indicate_reg = 1'b0;
										end
            
            IDLE_DISPARITY_WRONG: 		begin
											if (tx_disparity == NEGATIVE)
												tx_code_group_reg = K28_5_RD_NEG;
											else
												tx_code_group_reg = K28_5_RD_POS;
											tx_even_reg = 1'b1;
											tx_disparity_reg = (tx_disparity == NEGATIVE) ? POSITIVE : NEGATIVE;
											TX_OSET_indicate_reg = 1'b0;
										end
            
            IDLE_DISPARITY_OK: 			begin
											if (tx_disparity == NEGATIVE)
												tx_code_group_reg = K28_5_RD_NEG;
											else
												tx_code_group_reg = K28_5_RD_POS;
											tx_even_reg = 1'b1;
											tx_disparity_reg = (tx_disparity == NEGATIVE) ? POSITIVE : NEGATIVE;
											TX_OSET_indicate_reg = 1'b0;
										end
            
            IDLE_I1B: 					begin
											if (tx_o_set == OS_LI) begin
												tx_code_group_reg = D6_5; // /LI1/ uses D6.5 (disparity neutral)
											end else begin
												tx_code_group_reg = D5_6; // /I1/ uses D5.6 (disparity neutral) 
											end
											tx_even_reg = 1'b0;         // FALSE
											tx_disparity_reg = tx_disparity;
											TX_OSET_indicate_reg = cg_timer_done;
										end
            
            IDLE_I2B:	 				begin
											if (tx_o_set == OS_LI) begin
												// /LI2/ uses D26.4 which has disparity
												if (tx_disparity == NEGATIVE)
													tx_code_group_reg = D26_4_RD_NEG;
												else
													tx_code_group_reg = D26_4_RD_POS;
												tx_disparity_reg = (tx_disparity == NEGATIVE) ? POSITIVE : NEGATIVE;
											end else begin
												tx_code_group_reg = D16_2; // /I2/ uses D16.2 (disparity neutral)
												tx_disparity_reg = tx_disparity; // D16.2 is neutral => maintain same disparity
											end
											tx_even_reg = 1'b0;
											TX_OSET_indicate_reg = cg_timer_done;
										end
            
            DATA_GO: 					begin
											encode_enable = 1'b1;
											encode_data_in = TXD;
											encode_is_control = 1'b0;
											tx_code_group_reg = encode_code_group_out;
											tx_even_reg = tx_even;
											tx_disparity_reg = encode_disparity_out;
											TX_OSET_indicate_reg = cg_timer_done;
										end
            
            default: 					begin
											TX_OSET_indicate_reg = 1'b0;
										end
        endcase
    end
    
    // Output registers
    always_ff @(posedge clk or negedge rst_n) 
	begin
        if (!rst_n) 
		begin
            tx_code_group    <= 10'h000;
            tx_even          <= 1'b1;       // Start with even
            tx_disparity     <= NEGATIVE;   // Start with negative disparity
            TX_OSET_indicate <= 1'b0;
        end 
		else 
		begin
            tx_code_group    <= tx_code_group_reg;
            tx_even          <= tx_even_reg; 
            tx_disparity     <= tx_disparity_reg;
            TX_OSET_indicate <= TX_OSET_indicate_reg;
        end
    end

    // Status outputs
    assign current_state = state;
    assign state_change  = state_change_reg;
endmodule