/*
 * 8B/10B Decoder Module  
 * IEEE 802.3-2022 Clause 36 Implementation
 * 
 * Synthesizable RTL using lookup tables loaded via $readmemb
 */

module decoder_8b10b (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic [9:0]  code_group_in,   // 10-bit encoded input (abcdeifghj)
    output logic [7:0]  data_out,        // Decoded data byte (HGFEDCBA)
    output logic        is_control_out,  // 1=K code, 0=D code  
    output logic        disparity_out,   // Current running disparity
    output logic        decode_error,    // Decoding error flag (invalid code group)
    output logic        disparity_error  // Running disparity error flag
);

    // Running disparity: 0=negative, 1=positive
    logic running_disparity;
    
    // Decoder lookup tables - 10-bit entry format: {valid, is_control, 8-bit data}
    logic [9:0] decode_table_rd_neg [0:1023];  // Decode table for RD-
    logic [9:0] decode_table_rd_pos [0:1023];  // Decode table for RD+
    
    // Initialize lookup tables from files
    initial begin
        // Load decode tables using $readmemb
        $readmemb("decode_table_rd_neg.mem", decode_table_rd_neg);
        $readmemb("decode_table_rd_pos.mem", decode_table_rd_pos);
    end
    
    // Decode lookup signals
    logic [9:0] decode_entry_correct_rd, decode_entry_wrong_rd;
    logic       code_found_correct_rd, code_found_wrong_rd;
    logic       is_control_correct_rd, is_control_wrong_rd;
    logic [7:0] decoded_data_correct_rd, decoded_data_wrong_rd;
    
    // Final decode signals
    logic [7:0] decoded_data;
    logic       is_control_code;
    logic       code_found;
    logic       correct_disparity;
    
    // Combinational decode logic
    always_comb 
	begin
        // Lookup in both disparity tables
        decode_entry_correct_rd = running_disparity ? decode_table_rd_pos[code_group_in] : 
                                                     decode_table_rd_neg[code_group_in];
        decode_entry_wrong_rd   = running_disparity ? decode_table_rd_neg[code_group_in] : 
                                                     decode_table_rd_pos[code_group_in];
        
        // Extract fields from lookup results
        code_found_correct_rd    = decode_entry_correct_rd[9];
        is_control_correct_rd    = decode_entry_correct_rd[8];
        decoded_data_correct_rd  = decode_entry_correct_rd[7:0];
        
        code_found_wrong_rd      = decode_entry_wrong_rd[9];
        is_control_wrong_rd      = decode_entry_wrong_rd[8];
        decoded_data_wrong_rd    = decode_entry_wrong_rd[7:0];
        
        // Determine final decode result
        if (code_found_correct_rd) 
		begin
            // Found with correct running disparity
            code_found = 1'b1;
            correct_disparity = 1'b1;
            is_control_code = is_control_correct_rd;
            decoded_data = decoded_data_correct_rd;
        end 
		else if (code_found_wrong_rd) 
		begin
            // Found with wrong running disparity
            code_found = 1'b1;
            correct_disparity = 1'b0;
            is_control_code = is_control_wrong_rd;
            decoded_data = decoded_data_wrong_rd;
        end 
		else 
		begin
            // Not found in either table - invalid code group
            code_found = 1'b0;
            correct_disparity = 1'b0;
            is_control_code = 1'b0;
            decoded_data = 8'h00;
        end
        
        // Generate error flags
        decode_error = ~code_found;
        disparity_error = code_found & ~correct_disparity;
    end
    
    // Calculate new running disparity (same logic as encoder)
    logic [3:0] ones_count;
    logic new_disparity;
    
    always_comb 
	begin
        // Count ones in received code group
        ones_count = code_group_in[9] + code_group_in[8] + code_group_in[7] + 
                     code_group_in[6] + code_group_in[5] + code_group_in[4] + 
                     code_group_in[3] + code_group_in[2] + code_group_in[1] + 
                     code_group_in[0];
        
        // Determine new disparity
        if (ones_count > 5)
            new_disparity = 1'b1;      // Positive disparity
        else if (ones_count < 5) 
            new_disparity = 1'b0;      // Negative disparity
        else
            new_disparity = running_disparity; // Neutral - maintain current
    end
    
    always_ff @(posedge clk or negedge rst_n) 
	begin
        if (!rst_n) 
		begin
            running_disparity <= 1'b0;  // Start with negative disparity
            data_out <= 8'h00;
            is_control_out <= 1'b0;
            disparity_out <= 1'b0;
        end 
		else if (enable) 
		begin
            data_out <= decoded_data;
            is_control_out <= is_control_code;
            // Update running disparity based on received code group
            // As per spec, disparity is updated regardless of validity
            running_disparity <= new_disparity;
            disparity_out <= running_disparity;
        end
    end

endmodule