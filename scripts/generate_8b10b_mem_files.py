#!/usr/bin/env python3
"""
8B/10B Code Group Memory File Generator Parses the 8b_10b_code_groups_pcs.txt file and generates all required .mem files for the encoder_8b10b.sv and decoder_8b10b.sv modules.
"""

import re
import os

def parse_code_groups_file(filename):
    """Parse the 8B/10B code groups text file"""
    data_codes = {}  # {octet_hex: {'rd_neg': 10bit_code, 'rd_pos': 10bit_code, 'name': code_name}}
    ctrl_codes = {}  # Same structure for control codes
    
    try:
        with open(filename, 'r') as f:
            for line in f:
                line = line.strip()
                
                # Skip comments and empty lines
                if line.startswith('#') or not line:
                    continue
                
                # Parse line format: CODE_NAME OCTET_HEX RD_NEG_ABCDEI RD_NEG_FGHJ RD_POS_ABCDEI RD_POS_FGHJ
                parts = line.split()
                if len(parts) != 6:
                    continue
                    
                code_name = parts[0]
                octet_hex = parts[1]
                rd_neg_abcdei = parts[2]
                rd_neg_fghj = parts[3]  
                rd_pos_abcdei = parts[4]
                rd_pos_fghj = parts[5]
                
                # Combine 6-bit and 4-bit parts to form 10-bit codes
                rd_neg_code = rd_neg_abcdei + rd_neg_fghj
                rd_pos_code = rd_pos_abcdei + rd_pos_fghj
                
                # Convert hex string to integer
                octet_val = int(octet_hex, 16)
                
                # Store the code group information
                code_info = {
                    'rd_neg': rd_neg_code,
                    'rd_pos': rd_pos_code,
                    'name': code_name
                }
                
                # Determine if it's data or control code
                if code_name.startswith('D'):
                    data_codes[octet_val] = code_info
                elif code_name.startswith('K'):
                    ctrl_codes[octet_val] = code_info
                    
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found!")
        return None, None
    except Exception as e:
        print(f"Error parsing file: {e}")
        return None, None
        
    return data_codes, ctrl_codes

def write_encoder_mem_files(data_codes, ctrl_codes):
    """Generate memory files for the encoder module"""
    
    # Initialize 256-entry arrays with default values
    data_rd_neg = ['0000000000'] * 256
    data_rd_pos = ['0000000000'] * 256
    ctrl_rd_neg = ['0000000000'] * 256  
    ctrl_rd_pos = ['0000000000'] * 256
    
    # Fill data code arrays
    for octet, info in data_codes.items():
        data_rd_neg[octet] = info['rd_neg']
        data_rd_pos[octet] = info['rd_pos']
    
    # Fill control code arrays  
    for octet, info in ctrl_codes.items():
        ctrl_rd_neg[octet] = info['rd_neg']
        ctrl_rd_pos[octet] = info['rd_pos']
    
    # Write encoder memory files
    files = [
        ('data_table_rd_neg.mem', data_rd_neg),
        ('data_table_rd_pos.mem', data_rd_pos),
        ('ctrl_table_rd_neg.mem', ctrl_rd_neg),
        ('ctrl_table_rd_pos.mem', ctrl_rd_pos)
    ]
    
    for filename, data_array in files:
        with open(filename, 'w') as f:
            f.write(f"// {filename} - Generated from 8b_10b_code_groups_pcs.txt\n")
            f.write(f"// Format: 10-bit binary code groups\n\n")
            
            for addr, code in enumerate(data_array):
                f.write(f"{code}\n")
        
        print(f"Generated: {filename}")

def write_decoder_mem_files(data_codes, ctrl_codes):
    """Generate memory files for the decoder module"""
    
    # Create reverse lookup dictionaries
    # Format: {10bit_code: {'data': 8bit_value, 'is_control': bool}}
    rd_neg_lookup = {}
    rd_pos_lookup = {}
    
    # Process data codes
    for octet, info in data_codes.items():
        rd_neg_code = info['rd_neg']
        rd_pos_code = info['rd_pos']
        
        rd_neg_lookup[rd_neg_code] = {'data': octet, 'is_control': False}
        rd_pos_lookup[rd_pos_code] = {'data': octet, 'is_control': False}
    
    # Process control codes
    for octet, info in ctrl_codes.items():
        rd_neg_code = info['rd_neg']
        rd_pos_code = info['rd_pos']
        
        rd_neg_lookup[rd_neg_code] = {'data': octet, 'is_control': True}
        rd_pos_lookup[rd_pos_code] = {'data': octet, 'is_control': True}
    
    # Generate 1024-entry decoder tables (for 10-bit address space)
    # Format: {valid_bit, control_bit, 8bit_data} = 10 bits total
    decode_rd_neg = ['0000000000'] * 1024
    decode_rd_pos = ['0000000000'] * 1024
    
    # Fill RD- decoder table
    for code_str, info in rd_neg_lookup.items():
        code_int = int(code_str, 2)  # Convert binary string to integer
        if code_int < 1024:  # Safety check
            valid_bit = '1'
            control_bit = '1' if info['is_control'] else '0'
            data_bits = format(info['data'], '08b')  # 8-bit binary
            decode_rd_neg[code_int] = valid_bit + control_bit + data_bits
    
    # Fill RD+ decoder table  
    for code_str, info in rd_pos_lookup.items():
        code_int = int(code_str, 2)  # Convert binary string to integer
        if code_int < 1024:  # Safety check
            valid_bit = '1'
            control_bit = '1' if info['is_control'] else '0'
            data_bits = format(info['data'], '08b')  # 8-bit binary
            decode_rd_pos[code_int] = valid_bit + control_bit + data_bits
    
    # Write decoder memory files
    decoder_files = [
        ('decode_table_rd_neg.mem', decode_rd_neg),
        ('decode_table_rd_pos.mem', decode_rd_pos)
    ]
    
    for filename, data_array in decoder_files:
        with open(filename, 'w') as f:
            f.write(f"// {filename} - Generated from 8b_10b_code_groups_pcs.txt\n")
            f.write(f"// Format: {{valid_bit, control_bit, 8bit_data}}\n")
            f.write(f"// Address range: 0-1023 (10-bit code group value)\n\n")
            
            for addr, entry in enumerate(data_array):
                f.write(f"{entry}\n")
        
        print(f"Generated: {filename}")

def main():
    """Main function"""
    input_file = "8b_10b_code_groups_pcs.txt"
    
    print("8B/10B Code Group Memory File Generator")
    print("="*50)
    
    # Parse the input file
    print(f"Parsing: {input_file}")
    data_codes, ctrl_codes = parse_code_groups_file(input_file)
    
    if data_codes is None or ctrl_codes is None:
        print("Failed to parse input file!")
        return
    
    print(f"Found {len(data_codes)} data codes and {len(ctrl_codes)} control codes")
    
    # Generate encoder memory files
    print("\nGenerating encoder memory files...")
    write_encoder_mem_files(data_codes, ctrl_codes)
    
    # Generate decoder memory files  
    print("\nGenerating decoder memory files...")
    write_decoder_mem_files(data_codes, ctrl_codes)
    
    print(f"\nAll memory files generated successfully!")
    print("Files created:")
    print("- data_table_rd_neg.mem")
    print("- data_table_rd_pos.mem") 
    print("- ctrl_table_rd_neg.mem")
    print("- ctrl_table_rd_pos.mem")
    print("- decode_table_rd_neg.mem")
    print("- decode_table_rd_pos.mem")

if __name__ == "__main__":
    main()