/*
 * Timer Module
 * IEEE 802.3-2022 Clause 36 EEE Timer Implementation
 * 
 * Generic timer module for TQ, TW, and WF timers
 * Timer durations:
 * TQ Timer: 5μs (Quiet Timer)
 * TW Timer: 1μs (Wake Timer) 
 * WF Timer: 50ms (Wake Fault Timer)
 */

import pcs_pkg::*;

module timer_module #(
    parameter int TIMER_VALUE = 1000,  // Timer duration in clock cycles
    parameter int COUNTER_WIDTH = 32   // Counter width (adjustable for different timer ranges)
)(
    input  logic	clk,
    input  logic	rst_n,
    input  logic	start,      // Start timer
    output logic	done        // Timer done
);

    // Internal counter
    logic [COUNTER_WIDTH-1:0] counter;
    
    timer_state_t timer_state;
    
    // Timer state machine
    always_ff @(posedge clk or negedge rst_n) 
	begin
        if (!rst_n) 
		begin
            timer_state <= TIMER_IDLE;
            counter 	<= '0;
            done 		<= 1'b0;
        end 
		else 
		begin
            case (timer_state)
                TIMER_IDLE: 	begin
									done <= 1'b0;
									if (start) 
									begin
										timer_state <= TIMER_RUNNING;
										counter 	<= TIMER_VALUE - 1;  // Load timer value
									end
								end
                
                TIMER_RUNNING: 	begin
									if (counter == '0) 
									begin
										timer_state <= TIMER_DONE;
										done 		<= 1'b1;
									end 
									else 
									begin
										counter <= counter - 1;
									end
								end
                
                TIMER_DONE: 	begin
									// Stay in done state until start is deasserted
									if (!start) 
									begin
										timer_state <= TIMER_IDLE;
										done 		<= 1'b0;
									end
								end
                
                default: 		begin
									timer_state <= TIMER_IDLE;
									done <= 1'b0;
								end
            endcase
        end
    end

endmodule