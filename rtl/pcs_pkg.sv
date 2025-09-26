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
	
	// Transmit Code-Group State Machine States (Figure 36-6)
	typedef enum logic [4:0] {
		GENERATE_CODE_GROUPS	= 5'h00,
		SPECIAL_GO          	= 5'h01,
		CONFIGURATION_C1A   	= 5'h02,
		CONFIGURATION_C1B   	= 5'h03,
		CONFIGURATION_C1C   	= 5'h04,
		CONFIGURATION_C1D   	= 5'h05,
		CONFIGURATION_C2A   	= 5'h06,
		CONFIGURATION_C2B   	= 5'h07,
		CONFIGURATION_C2C   	= 5'h08,
		CONFIGURATION_C2D   	= 5'h09,
		IDLE_DISPARITY_TEST 	= 5'h0A,
		IDLE_DISPARITY_WRONG	= 5'h0B,
		IDLE_DISPARITY_OK   	= 5'h0C,
		IDLE_I1B            	= 5'h0D,
		IDLE_I2B            	= 5'h0E,
		DATA_GO             	= 5'h0F
	} tx_code_group_state_t;
	
	// Running Disparity Values
	typedef enum logic {
		NEGATIVE = 1'b0,
		POSITIVE = 1'b1
	} disparity_t;
	
	// Special Code-Groups (K-codes) - from IEEE Table 36-2
	typedef enum logic [9:0] {
		K28_5_RD_NEG = 10'b0011111010,  // K28.5 RD- - comma pattern 
		K28_5_RD_POS = 10'b1100000101,  // K28.5 RD+ - comma pattern
		K23_7_RD_NEG = 10'b1110101000,  // K23.7 RD- - /R/ Carrier Extend
		K23_7_RD_POS = 10'b0001010111,  // K23.7 RD+ - /R/ Carrier Extend
		K27_7_RD_NEG = 10'b1101101000,  // K27.7 RD- - /S/ Start of Packet
		K27_7_RD_POS = 10'b0010010111,  // K27.7 RD+ - /S/ Start of Packet  
		K29_7_RD_NEG = 10'b1011101000,  // K29.7 RD- - /T/ End of Packet
		K29_7_RD_POS = 10'b0100010111,  // K29.7 RD+ - /T/ End of Packet
		K30_7_RD_NEG = 10'b0111101000,  // K30.7 RD- - /V/ Error Propagation
		K30_7_RD_POS = 10'b1000010111   // K30.7 RD+ - /V/ Error Propagation
	} special_codegroup_t;
	
	// Data Code-Groups for specific patterns - from IEEE Table 36-1
	typedef enum logic [9:0] {
		D21_5 = 10'b1010101010,  // D21.5 used in C1 config (disparity neutral)
		D2_2_RD_NEG = 10'b1011010101,  // D2.2 RD- used in C2 config  
		D2_2_RD_POS = 10'b0100100101,  // D2.2 RD+ used in C2 config
		D5_6 = 10'b1010010110,  // D5.6 IDLE /I1/ (disparity neutral)
		D16_2 = 10'b0100110101, // D16.2 IDLE /I2/ (disparity neutral)
		D6_5 = 10'b0110011010,  // D6.5 LPI /LI1/ (disparity neutral) 
		D26_4_RD_NEG = 10'b0101101101, // D26.4 RD- LPI /LI2/
		D26_4_RD_POS = 10'b0101100010  // D26.4 RD+ LPI /LI2/
	} data_codegroup_t;
endpackage