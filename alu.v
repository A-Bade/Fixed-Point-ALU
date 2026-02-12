module alu (
	input i_clk,
	input i_rst_n,
	input i_valid,
	input signed [11:0] i_data_a,
	input signed [11:0] i_data_b,
	input [2:0] i_inst,
	output o_valid,
	output [11:0] o_data,
	output o_overflow
);

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
reg [11:0] o_data_w, o_data_r;
reg o_valid_w, o_valid_r;
reg o_overflow_w, o_overflow_r;

// ---- Add your own wires and registers here if needed ---- //
reg signed [11:0] a_r, b_r;
reg [2:0] inst_r;
reg valid_r;
reg signed [23:0] result_ext;
reg signed [11:0] result_final;
reg overflow_w;
reg signed [23:0] mac_acc;
reg mac_overflow;
reg signed [23:0] mac_next;
reg [2:0] prev_inst;
reg mac_overflow_next;

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
assign o_valid = o_valid_r;
assign o_data = o_data_r;
assign o_overflow = o_overflow_r;

// ---- Add your own wire data assignments here if needed ---- //

always @(negedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        a_r <= 0;
        b_r <= 0;
        inst_r <= 0;
        valid_r <= 0;
    end
    else begin
        valid_r <= i_valid;
        if (i_valid) begin
            a_r <= i_data_a;
            b_r <= i_data_b;
            inst_r <= i_inst;
        end
    end
end

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

always @(*) begin
    result_ext = 0;
    result_final = 0;
    overflow_w = 0;

    case (inst_r)

        // ADD
        3'b000: begin
            result_ext = a_r + b_r;
            overflow_w = (a_r[11] == b_r[11]) && (result_ext[11] != a_r[11]);
        end

        // SUB
        3'b001: begin
            result_ext = a_r - b_r;
            overflow_w = (a_r[11] != b_r[11]) && (result_ext[11] != a_r[11]);
        end

        // MUL 
        3'b010: begin
            result_ext = a_r * b_r; // 24bit (duh)
            result_ext = result_ext + 24'sd16; // we round those
            result_ext = result_ext >>> 5;
            overflow_w = (result_ext > 24'sd2047) || (result_ext < -24'sd2048);
        end

        3'b011: begin
            // MAC
            result_ext = mac_acc;
            overflow_w = mac_overflow;
        end

        // XNOR
        3'b100: begin
            result_ext = ~(a_r ^ b_r);
        end

        // ReLU
        3'b101: begin
            result_ext = (a_r[11]) ? 0 : a_r;
        end

        // MEAN
        3'b110: begin
            result_ext = a_r + b_r;
            result_ext = result_ext >>> 1;
            overflow_w = (result_ext > 24'sd2047) || (result_ext < -24'sd2048);
        end

        // ABS MAX
        3'b111: begin
            result_ext =
                ($signed(a_r) < 0 ? -a_r : a_r) >
                ($signed(b_r) < 0 ? -b_r : b_r)
                ? ($signed(a_r) < 0 ? -a_r : a_r)
                : ($signed(b_r) < 0 ? -b_r : b_r);
        end

        default: begin
            result_ext = 0;
        end

    endcase

    result_final = result_ext[11:0];
end

always @(*) begin
    if (inst_r == 3'b011) begin
        if (prev_inst != 3'b011)
            mac_next = ((a_r * b_r + 24'sd16) >>> 5);
        else
            mac_next = mac_acc + ((a_r * b_r + 24'sd16) >>> 5);
    end
    else begin
        mac_next = 0;
    end
end

always @(*) begin
    if (inst_r == 3'b011) begin
        // ignore old overflow
        if (prev_inst != 3'b011) begin
            if (mac_next > 24'sd2047 || mac_next < -24'sd2048)
                mac_overflow_next = 1;
            else
                mac_overflow_next = 0;
        end
        // Continuing MAC sequence
        else begin
            if (mac_overflow)
                mac_overflow_next = 1;
            else if (mac_next > 24'sd2047 || mac_next < -24'sd2048)
                mac_overflow_next = 1;
            else
                mac_overflow_next = 0;
        end
    end else begin
        mac_overflow_next = 0;
    end
end


// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_data_r <= 0;
        o_valid_r <= 0;
        o_overflow_r <= 0;
        mac_acc <= 0;
        mac_overflow <= 0;
        prev_inst <= 0;
    end
    else begin
        o_valid_r <= valid_r;

        if (valid_r) begin

            // mac
            if (inst_r == 3'b011) begin

                // Reset on new MAC sequence
                if (prev_inst != 3'b011) begin
                    mac_acc <= 0;
                    mac_overflow <= 0;
                end

                mac_overflow <= mac_overflow_next;

                if (!mac_overflow_next)
                    mac_acc <= mac_next;

                o_data_r <= mac_next[11:0];
                o_overflow_r <= mac_overflow_next;
            end
            else begin
                // ---------- NON-MAC PATH ----------
                mac_acc <= 0;
                mac_overflow <= 0;
                o_data_r <= result_final;
                o_overflow_r <= overflow_w;
            end

            prev_inst <= inst_r;
        end
        else begin
            o_overflow_r <= 0;
        end
    end
end

endmodule

