/*
 * Package containing type definitions for PCS modules
 */
package pcs_pkg;
	// Ordered Set Types
	typedef enum logic [3:0] {
		OS_C    = 4'h0,  // Configuration ordered set
		OS_I    = 4'h1,  // IDLE ordered set  
		OS_S    = 4'h2,  // Start of Packet Delimiter
		OS_T    = 4'h3,  // End of Packet Delimiter part 1
		OS_R    = 4'h4,  // End of Packet Delimiter part 2/3, Carrier Extend
		OS_V    = 4'h5,  // Error Propagation
		OS_D    = 4'h6,  // Data code-group
		OS_LI   = 4'h7   // Low Power Idle (EEE)
	} ordered_set_t;
	
	// xmit variable values (from Auto-Negotiation)
	typedef enum logic [1:0] {
		XMIT_CONFIGURATION 	= 2'b00,
		XMIT_IDLE         	= 2'b01,
		XMIT_DATA         	= 2'b10
	} xmit_type_t;
	
	// State Machine States
	typedef enum logic [4:0] {
		TX_TEST_XMIT         	= 5'h00,
		CONFIGURATION        	= 5'h01, 
		IDLE                 	= 5'h02,
		XMIT_DATA           	= 5'h03,
		ALIGN_ERR_START     	= 5'h04,
		START_ERROR         	= 5'h05,
		TX_DATA_ERROR       	= 5'h06,
		START_OF_PACKET     	= 5'h07,
		TX_PACKET           	= 5'h08,  // Timeless state
		TX_DATA             	= 5'h09,
		END_OF_PACKET_NOEXT 	= 5'h0A,
		EPD2_NOEXT          	= 5'h0B,
		EPD3                	= 5'h0C,
		END_OF_PACKET_EXT   	= 5'h0D,
		EXTEND_BY_1         	= 5'h0E,
		CARRIER_EXTEND      	= 5'h0F,
		XMIT_LPIDLE         	= 5'h10   // EEE Low Power Idle
	} tx_ordered_set_state_t;
endpackage