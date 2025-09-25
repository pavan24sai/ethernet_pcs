/*
 * 8B/10B Encoder Module
 * IEEE 802.3-2022 Clause 36 Implementation
 * 
 * Synthesizable RTL using lookup tables loaded via $readmemb
 */

module encoder_8b10b (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic [7:0]  data_in,        // Input data byte (HGFEDCBA)
    input  logic        is_control,     // 1=K code, 0=D code
    output logic [9:0]  code_group_out, // 10-bit encoded output (abcdeifghj)
    output logic        disparity_out,  // Current running disparity
    output logic        encode_error    // Encoding error flag
);

    // Running disparity: 0=negative, 1=positive  
    logic running_disparity;
    
    // Lookup table memories - loaded from file
    // Format: [address] = {6'b_abcdei, 4'b_fghj}
    logic [9:0] data_table_rd_neg [0:255];   // Data codes for RD-
    logic [9:0] data_table_rd_pos [0:255];   // Data codes for RD+
    logic [9:0] ctrl_table_rd_neg [0:255];   // Control codes for RD-  
    logic [9:0] ctrl_table_rd_pos [0:255];   // Control codes for RD+
    
    // Initialize lookup tables from files
    initial begin
        // Load code group tables using $readmemb
        $readmemb("data_table_rd_neg.mem", data_table_rd_neg);
        $readmemb("data_table_rd_pos.mem", data_table_rd_pos);
        $readmemb("ctrl_table_rd_neg.mem", ctrl_table_rd_neg);  
        $readmemb("ctrl_table_rd_pos.mem", ctrl_table_rd_pos);
    end
    
    // Lookup table access
    logic [9:0] data_code_rd_neg, data_code_rd_pos;
    logic [9:0] ctrl_code_rd_neg, ctrl_code_rd_pos;
    logic [9:0] selected_code_group;
    
    // Combinational lookup logic
    always_comb 
	begin
        // Access lookup tables
        data_code_rd_neg = data_table_rd_neg[data_in];
        data_code_rd_pos = data_table_rd_pos[data_in];
        ctrl_code_rd_neg = ctrl_table_rd_neg[data_in];
        ctrl_code_rd_pos = ctrl_table_rd_pos[data_in];
        
        // Select code group based on control flag and running disparity
        if (is_control) 
		begin
            if (running_disparity == 1'b0)
                selected_code_group = ctrl_code_rd_neg;
            else
                selected_code_group = ctrl_code_rd_pos;
                
            // Check for valid control code (non-zero entry)
            encode_error = (selected_code_group == 10'h000);
        end 
		else 
		begin
            if (running_disparity == 1'b0)
                selected_code_group = data_code_rd_neg;
            else
                selected_code_group = data_code_rd_pos;
                
            encode_error = 1'b0; // All data codes are valid
        end
    end
    
    // Calculate new running disparity
    logic [3:0] ones_count;
    logic new_disparity;
    
    always_comb 
	begin
        // Count ones in the selected code group
        ones_count = selected_code_group[9] + selected_code_group[8] + selected_code_group[7] + 
                     selected_code_group[6] + selected_code_group[5] + selected_code_group[4] + 
                     selected_code_group[3] + selected_code_group[2] + selected_code_group[1] + 
                     selected_code_group[0];
        
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
            code_group_out <= 10'h000;
            disparity_out <= 1'b0;
        end 
		else if (enable) 
		begin
            code_group_out <= selected_code_group;
            running_disparity <= new_disparity;
            disparity_out <= running_disparity;
        end
    end

endmodule