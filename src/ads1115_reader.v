//=============================================================================
//  ads1115_reader.v -- Maestro I2C + secuenciador de lectura del ADS1115
//  Target : Cyclone IV EP4CE6E22C8N @ 50 MHz    Bus I2C a 100 kHz
//
//  Realiza un ciclo completo de medida por cada pulso en 'start':
//     1) Escribe el registro de configuracion (conversion unica, AIN0, PGA)
//     2) Espera el tiempo de conversion
//     3) Apunta al registro de conversion
//     4) Lee los 2 bytes del resultado
//     5) Emite 'data_valid' con el codigo en 'data_out'
//
//  Salidas SCL/SDA en DRENADOR ABIERTO: solo tiran a 0, nunca fuerzan un 1.
//  Requiere resistencias de pull-up externas de 4.7 kOhm a 3.3 V.
//=============================================================================
`timescale 1ns/1ps

module ads1115_reader #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer I2C_FREQ  = 100_000,
    parameter [6:0]   DEV_ADDR  = 7'h48,        // ADDR a GND
    // Registro de configuracion del ADS1115:
    //   OS=1 (inicia conversion) | MUX=100 (AIN0 vs GND) | PGA=001 (+/-4.096 V)
    //   MODE=1 (conversion unica) | DR=100 (128 SPS) | COMP_QUE=11 (deshabilitado)
    parameter [7:0]   CFG_MSB   = 8'hC3,
    parameter [7:0]   CFG_LSB   = 8'h83,
    // Espera de conversion: 128 SPS -> 7.8 ms. Usamos 10 ms de margen.
    parameter integer CONV_WAIT = 500_000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,        // pulso de 1 ciclo
    output wire [15:0] data_out,     // codigo en complemento a 2
    output reg         data_valid,   // pulso de 1 ciclo
    output reg         ack_ok,       // 1 = el ADS1115 contesto el ACK de direccion
    output wire        busy,
    inout  wire        scl,
    inout  wire        sda
);

    //=========================================================================
    //  MOTOR I2C DE BAJO NIVEL (nivel de byte)
    //=========================================================================
    localparam [1:0] C_START = 2'd0,
                     C_WR    = 2'd1,
                     C_RD    = 2'd2,
                     C_STOP  = 2'd3;

    // Un tick por cada cuarto de periodo de SCL
    localparam integer QDIV = CLK_FREQ / (I2C_FREQ * 4);   // 125

    reg  [1:0] cmd;          // comando presentado al motor
    reg  [7:0] wr_byte;
    reg        rd_nack;
    reg        go;

    reg  [1:0] cmd_r;
    reg  [7:0] shreg;
    reg        nack_r;
    reg  [8:0] qcnt;
    reg  [1:0] phase;        // 0..3 (cuartos del periodo de SCL)
    reg  [3:0] bitc;         // 0..7 datos, 8 = ciclo de ACK
    reg        active;
    reg        eng_done;
    reg  [7:0] rd_byte;
    reg        slave_ack;
    reg        hold_low;      // mantiene SCL en bajo ENTRE comandos de una
                              // misma transaccion; sin esto el bus generaria
                              // un pulso espurio de SCL en cada byte.

    wire qtick = (qcnt == QDIV[8:0] - 1'b1);

    // --- Salidas en drenador abierto -----------------------------------------
    reg scl_low, sda_low;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;

    // SCL: bajo en los cuartos 0 y 3; alto en 1 y 2.
    // Excepcion: en STOP debe quedarse alto tras el cuarto 0.
    always @(*) begin
        if (!active)                 scl_low = hold_low;
        else if (cmd_r == C_STOP)    scl_low = (phase == 2'd0);
        else                         scl_low = (phase == 2'd0) || (phase == 2'd3);
    end

    // SDA segun el comando en curso
    always @(*) begin
        sda_low = 1'b0;
        if (active) begin
            case (cmd_r)
                // START: SDA cae mientras SCL esta alto
                C_START: sda_low = (phase >= 2'd2);
                // STOP : SDA sube mientras SCL esta alto
                C_STOP : sda_low = (phase <= 2'd1);
                // Escritura: MSB primero; en el ciclo 8 se libera para el ACK
                C_WR   : sda_low = (bitc < 4'd8) ? ~shreg[7] : 1'b0;
                // Lectura: se libera; en el ciclo 8 el maestro da ACK o NACK
                C_RD   : sda_low = (bitc < 4'd8) ? 1'b0 : ~nack_r;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qcnt <= 9'd0;  phase <= 2'd0;  bitc <= 4'd0;
            active <= 1'b0; eng_done <= 1'b0; hold_low <= 1'b0;
            cmd_r <= C_STOP; shreg <= 8'h00; nack_r <= 1'b1;
            rd_byte <= 8'h00; slave_ack <= 1'b0;
        end else begin
            eng_done <= 1'b0;

            if (!active) begin
                if (go) begin
                    cmd_r  <= cmd;
                    shreg  <= wr_byte;
                    nack_r <= rd_nack;
                    active <= 1'b1;
                    phase  <= 2'd0;
                    bitc   <= 4'd0;
                    qcnt   <= 9'd0;
                end
            end else begin
                if (!qtick) begin
                    qcnt <= qcnt + 1'b1;
                end else begin
                    qcnt  <= 9'd0;
                    phase <= phase + 1'b1;

                    // Muestreo del bus en el cuarto 2 (SCL alto y estable)
                    if (phase == 2'd2) begin
                        if (cmd_r == C_WR && bitc == 4'd8) slave_ack <= ~sda;
                        if (cmd_r == C_RD && bitc <  4'd8) rd_byte <= {rd_byte[6:0], sda};
                    end

                    // Fin del cuarto 3: avanzar de bit o terminar el comando
                    if (phase == 2'd3) begin
                        if (cmd_r == C_START || cmd_r == C_STOP) begin
                            active   <= 1'b0;
                            eng_done <= 1'b1;
                            hold_low <= (cmd_r != C_STOP);
                        end else begin
                            if (cmd_r == C_WR) shreg <= {shreg[6:0], 1'b0};
                            if (bitc == 4'd8) begin
                                active   <= 1'b0;
                                eng_done <= 1'b1;
                                hold_low <= 1'b1;
                            end else begin
                                bitc <= bitc + 1'b1;
                            end
                        end
                    end
                end
            end
        end
    end

    //=========================================================================
    //  SECUENCIADOR DEL ADS1115 (nivel de transaccion)
    //=========================================================================
    localparam [4:0] S_DLY  = 5'd6,    // paso de espera de conversion
                     S_END  = 5'd16;   // paso final

    localparam [1:0] F_IDLE = 2'd0, F_GO = 2'd1, F_WAIT = 2'd2, F_DELAY = 2'd3;

    reg  [1:0]  fsm;
    reg  [4:0]  step;
    reg  [19:0] dly;
    reg  [7:0]  res_msb, res_lsb;

    // Decodificacion combinacional del paso -> comando I2C
    always @(*) begin
        cmd     = C_STOP;
        wr_byte = 8'h00;
        rd_nack = 1'b1;
        case (step)
            5'd0 :   cmd = C_START;
            5'd1 : begin cmd = C_WR; wr_byte = {DEV_ADDR, 1'b0}; end  // 0x90 escritura
            5'd2 : begin cmd = C_WR; wr_byte = 8'h01;            end  // puntero = config
            5'd3 : begin cmd = C_WR; wr_byte = CFG_MSB;          end
            5'd4 : begin cmd = C_WR; wr_byte = CFG_LSB;          end
            5'd5 :   cmd = C_STOP;
            // paso 6: espera de conversion (no genera trafico I2C)
            5'd7 :   cmd = C_START;
            5'd8 : begin cmd = C_WR; wr_byte = {DEV_ADDR, 1'b0}; end
            5'd9 : begin cmd = C_WR; wr_byte = 8'h00;            end  // puntero = conversion
            5'd10:   cmd = C_STOP;
            5'd11:   cmd = C_START;
            5'd12: begin cmd = C_WR; wr_byte = {DEV_ADDR, 1'b1}; end  // 0x91 lectura
            5'd13: begin cmd = C_RD; rd_nack = 1'b0;             end  // MSB, con ACK
            5'd14: begin cmd = C_RD; rd_nack = 1'b1;             end  // LSB, con NACK
            5'd15:   cmd = C_STOP;
            default: cmd = C_STOP;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm <= F_IDLE; step <= 5'd0; go <= 1'b0;
            data_valid <= 1'b0; dly <= 20'd0; ack_ok <= 1'b0;
            res_msb <= 8'h00; res_lsb <= 8'h00;
        end else begin
            go         <= 1'b0;
            data_valid <= 1'b0;

            case (fsm)
                F_IDLE: if (start) begin
                            step <= 5'd0;
                            fsm  <= F_GO;
                        end

                F_GO:   if (step == S_DLY) begin
                            dly <= 20'd0;
                            fsm <= F_DELAY;
                        end else if (step == S_END) begin
                            data_valid <= 1'b1;
                            fsm        <= F_IDLE;
                        end else begin
                            go  <= 1'b1;
                            fsm <= F_WAIT;
                        end

                F_WAIT: if (eng_done) begin
                            if (step == 5'd1)  ack_ok  <= slave_ack;  // ACK de 0x90
                            if (step == 5'd13) res_msb <= rd_byte;
                            if (step == 5'd14) res_lsb <= rd_byte;
                            step <= step + 1'b1;
                            fsm  <= F_GO;
                        end

                F_DELAY:if (dly == CONV_WAIT[19:0] - 1'b1) begin
                            step <= step + 1'b1;
                            fsm  <= F_GO;
                        end else begin
                            dly <= dly + 1'b1;
                        end
            endcase
        end
    end

    assign data_out = {res_msb, res_lsb};
    assign busy     = (fsm != F_IDLE);

endmodule
