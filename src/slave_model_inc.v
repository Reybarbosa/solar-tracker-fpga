module ads1115_slave_model #(
    parameter [6:0]  ADDR = 7'h48,
    parameter [15:0] CONV = 16'd19400        // 2.425 V en AIN0 -> 4.85 V de panel
)(
    inout wire scl,
    inout wire sda
);
    reg sda_low = 1'b0;
    assign sda = sda_low ? 1'b0 : 1'bz;

    reg [7:0] rx    = 8'h00;
    reg [7:0] txsr  = 8'h00;
    reg [3:0] bitn  = 4'd0;
    reg [3:0] bytn  = 4'd0;
    reg       xfer  = 1'b0;
    reg       rdm   = 1'b0;

    // START: SDA cae con SCL alto      STOP: SDA sube con SCL alto
    always @(negedge sda) if (scl === 1'b1) begin
        xfer <= 1'b1; bitn <= 4'd0; bytn <= 4'd0; rdm <= 1'b0; sda_low <= 1'b0;
    end
    always @(posedge sda) if (scl === 1'b1) begin
        xfer <= 1'b0; sda_low <= 1'b0;
    end

    always @(posedge scl) if (xfer) begin
        if (bitn < 4'd8) begin
            rx   <= {rx[6:0], (sda === 1'b1)};
            bitn <= bitn + 4'd1;
        end else begin
            bitn <= 4'd9;                       // el ACK ya fue muestreado
        end
    end

    always @(negedge scl) if (xfer) begin
        if (bitn == 4'd8) begin                 // se completaron los 8 bits
            if (bytn == 4'd0) begin
                sda_low <= (rx[7:1] == ADDR);   // ACK solo si coincide la direccion
                rdm     <= rx[0];
            end else if (!rdm) begin
                sda_low <= 1'b1;                // ACK del dato escrito
            end else begin
                sda_low <= 1'b0;                // en lectura el ACK lo da el maestro
            end
        end else if (bitn == 4'd9) begin        // fin del ciclo de ACK
            bitn <= 4'd0;
            bytn <= bytn + 4'd1;
            if (rdm) begin
                txsr    <= (bytn == 4'd0) ? CONV[15:8] : CONV[7:0];
                sda_low <= ~((bytn == 4'd0) ? CONV[15] : CONV[7]);
            end else begin
                sda_low <= 1'b0;
            end
        end else if (rdm && bytn > 4'd0) begin  // enviando: siguiente bit
            txsr    <= {txsr[6:0], 1'b0};
            sda_low <= ~txsr[6];
        end
    end
endmodule
