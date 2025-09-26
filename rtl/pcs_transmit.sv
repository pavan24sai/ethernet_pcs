/*
 * PCS Transmit Path Module
 * IEEE 802.3-2022 Clause 36 Implementation
 * 
 * This module integrates the PCS transmit ordered set state machine and 
 * transmit code-group state machine as specified in Figures 36-5 and 36-6.
 */

import pcs_pkg::*;

module pcs_transmit
(
    // Clock and Reset
    input  logic         clk,
    input  logic         rst_n,
    
    // Power-on and Management Reset  
    input  logic         power_on,
    input  logic         mr_main_reset,
    
    // GMII Interface (from MAC/Reconciliation)
    input  logic [7:0]   TXD,               // GMII transmit data
    input  logic         TX_EN,             // GMII transmit enable
    input  logic         TX_ER,             // GMII transmit error
    output logic         COL,               // GMII collision detection
    
    // Auto-Negotiation Interface
    input  xmit_type_t   xmit,              // CONFIGURATION, IDLE, or DATA
    input  logic         xmitCHANGE,        // xmit variable change detection
    input  logic [15:0]  tx_Config_Reg,    // Configuration register for /C/ ordered sets
    
    // EEE Support Interface
    input  logic         assert_lpidle,     // Low Power Idle assertion
    
    // Carrier Sense and Collision Detection
    input  logic         receiving,         // From PCS receive process
    
    // Timer Interface  
    input  logic         cg_timer_done,     // Code group timer (8ns nominal)
    
    // PMA Service Interface (Output)
    output logic [9:0]   tx_code_group,     // 10-bit code group to PMA
    output logic         tx_code_valid,     // Code group valid indication
    
    // Status and Control Outputs
    output logic         transmitting,      // Transmission status for carrier sense
    output logic         tx_even,          // Even/odd code group alignment
    output disparity_t   tx_disparity,     // Running disparity for PMA
    
    // Debug and Status
    output tx_ordered_set_state_t    tx_oset_state,
    output tx_code_group_state_t     tx_cg_state,
    output logic                     tx_oset_state_change,
    output logic                     tx_cg_state_change
);  
    // Interface between Ordered Set SM and Code Group SM
    ordered_set_t        tx_o_set;
    logic                TX_OSET_indicate;
    logic                tx_code_valid_int;
    
    // Code group valid -> successful encoding and timing
    assign tx_code_valid = tx_code_valid_int & cg_timer_done;
    
    //=========================================================================
    // PCS Transmit Ordered Set State Machine
    //=========================================================================
    
    pcs_tx_ordered_set u_tx_ordered_set (
        // Clock and Reset
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Power-on and Management Reset
        .power_on               (power_on),
        .mr_main_reset          (mr_main_reset),
        
        // Auto-Negotiation Interface
        .xmit                   (xmit),
        .xmitCHANGE             (xmitCHANGE),
        
        // GMII Interface Signals
        .TX_EN                  (TX_EN),
        .TX_ER                  (TX_ER),
        .TXD                    (TXD),
        
        // Timing and Control Signals
        .TX_OSET_indicate       (TX_OSET_indicate),    // From code group SM
        .tx_even                (tx_even),             // From code group SM
        .receiving              (receiving),           // From receive process
        
        // EEE Support
        .assert_lpidle          (assert_lpidle),
        
        // Output Interface
        .tx_o_set               (tx_o_set),            // To code group SM
        .transmitting           (transmitting),        // To carrier sense
        .COL                    (COL),                 // GMII collision output
        
        // Status and Debug
        .current_state          (tx_oset_state),
        .state_change           (tx_oset_state_change)
    );
    
    //=========================================================================
    // PCS Transmit Code-Group State Machine  
    //=========================================================================
    
    pcs_tx_code_group u_tx_code_group (
        // Clock and Reset
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Power-on and Management Reset
        .power_on               (power_on),
        .mr_main_reset          (mr_main_reset),
        
        // Interface with Ordered Set State Machine
        .tx_o_set               (tx_o_set),            // From ordered set SM
        .TX_OSET_indicate       (TX_OSET_indicate),    // Back to ordered set SM
        
        // Auto-Negotiation Interface
        .tx_Config_Reg          (tx_Config_Reg),
        
        // GMII Data Interface
        .TXD                    (TXD),
        
        // Timer Interface
        .cg_timer_done          (cg_timer_done),
        
        // Output Interface
        .tx_code_group          (tx_code_group),       // To PMA
        .tx_even                (tx_even),             // Back to ordered set SM & external
        .tx_disparity           (tx_disparity),        // To PMA
        
        // Status and Debug
        .current_state          (tx_cg_state),
        .state_change           (tx_cg_state_change)
    );

    //=========================================================================
    // Output Control Logic
    //=========================================================================
    always_ff @(posedge clk or negedge rst_n) 
	begin
        if (!rst_n) 
		begin
            tx_code_valid_int <= 1'b0;
        end 
		else 
		begin
            tx_code_valid_int <= !(power_on || mr_main_reset);
        end
    end
endmodule