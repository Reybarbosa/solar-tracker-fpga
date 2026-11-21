//=============================================================================
//  top_telemetry.v -- Subsistema de telemetria del seguidor solar
//  FPGA: Cyclone IV EP4CE6E22C8 (WaveShare Core EP4CE6) - reloj 50 MHz
//
//  Cadena de procesamiento:
//     panel 0-5V --[divisor R]--> ADS1115 --I2C--> FPGA --> ASCII --> UART -> HC-05
//
//  NOTA DE ALCANCE (honesta): el maestro I2C del ADS1115 NO esta incluido,
//  porque el enunciado pidio excluirlo. Aqui se define su CONTRATO de puertos
//  y se provee un generador de rampa (USE_STUB=1) para que el proyecto compile,
//  simule y se pueda probar contra el celular HOY MISMO. Poner USE_STUB=0
//  cuando el modulo ads1115_reader este disponible.
//=============================================================================
`timescale 1ns/1ps

module top_telemetry #(
    parameter integer CLK_FREQ    = 50_000_000,
    parameter integer BAUD        = 9600,
    parameter integer PERIOD_MS   = 500,   // periodo de refresco de telemetria
    parameter integer SCALE_NUM   = 1,     // divisor 10k/10k, k=1/2 -> mV = codigo/4
    parameter integer SCALE_SHIFT = 2,     // (ver cabecera de bin_to_ascii.v)
    parameter         USE_STUB    = 1'b1,
    // DIAG_I2C = 1 -> transmite "R=XXXX A" (codigo crudo + ACK) en vez de voltios
    parameter         DIAG_I2C    = 1'b0
)(
    input  wire  clk50,      // PIN_23  oscilador 50 MHz
    input  wire  rst_n,      // PIN_25  pulsador KEY (activo en bajo)
    inout  wire  i2c_scl,    // hacia ADS1115  (pull-up externo 4.7k a 3.3V)
    inout  wire  i2c_sda,    // hacia ADS1115  (pull-up externo 4.7k a 3.3V)
    output wire  uart_txd,   // hacia HC-05 RXD
    output wire  led_busy    // LED de la tarjeta (activo en bajo)
);

    //=========================================================================
    // Sincronizador de liberacion de reset (buena practica; evita metaestabilidad
    // al soltar el pulsador asincrono)
    //=========================================================================
    reg [1:0] rst_sync;
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) rst_sync <= 2'b00;
        else        rst_sync <= {rst_sync[0], 1'b1};
    end
    wire rst_n_s = rst_sync[1];

    //=========================================================================
    // Base de tiempo: un pulso cada PERIOD_MS milisegundos
    //=========================================================================
    localparam integer TICK_MAX = (CLK_FREQ/1000) * PERIOD_MS;  // 25_000_000

    reg  [25:0] ms_cnt;
    wire        tick = (ms_cnt == TICK_MAX - 1);

    always @(posedge clk50 or negedge rst_n_s) begin
        if (!rst_n_s)   ms_cnt <= 26'd0;
        else if (tick)  ms_cnt <= 26'd0;
        else            ms_cnt <= ms_cnt + 1'b1;
    end

    //=========================================================================
    // Interfaz con el lector del ADS1115 (contrato de puertos)
    //=========================================================================
    wire        adc_start;
    wire [15:0] adc_code;
    wire        adc_valid;

    generate
    if (USE_STUB) begin : g_adc_stub
        // Rampa de prueba: 0 -> 4.95 V en 11 pasos. Permite validar UART,
        // conversion BCD y enlace Bluetooth sin el I2C montado.
        reg [15:0] ramp;
        reg        vld;
        always @(posedge clk50 or negedge rst_n_s) begin
            if (!rst_n_s) begin
                ramp <= 16'd0;
                vld  <= 1'b0;
            end else begin
                vld <= 1'b0;
                if (adc_start) begin
                    ramp <= (ramp >= 16'd26400) ? 16'd0 : ramp + 16'd2640;
                    vld  <= 1'b1;
                end
            end
        end
        assign adc_code  = ramp;
        assign adc_valid = vld;
        assign adc_ack   = 1'b1;
        assign i2c_scl   = 1'bz;
        assign i2c_sda   = 1'bz;
    end else begin : g_adc_real
        // Contrato que debe cumplir el maestro I2C:
        //   adc_start : pulso de 1 ciclo -> lanza conversion + lectura
        //   adc_valid : pulso de 1 ciclo -> adc_code contiene el dato valido
        //   adc_code  : 16 bits en complemento a 2 del registro de conversion
        ads1115_reader u_adc (
            .clk        (clk50),
            .rst_n      (rst_n_s),
            .start      (adc_start),
            .data_out   (adc_code),
            .data_valid (adc_valid),
            .ack_ok     (adc_ack),
            .scl        (i2c_scl),
            .sda        (i2c_sda)
        );
    end
    endgenerate

    //=========================================================================
    // Registro de retencion: congela la muestra durante toda la trama ASCII
    //=========================================================================
    reg [15:0] adc_lat;
    always @(posedge clk50 or negedge rst_n_s) begin
        if (!rst_n_s)        adc_lat <= 16'd0;
        else if (adc_valid)  adc_lat <= adc_code;
    end

    //=========================================================================
    // Conversion binario -> ASCII
    //=========================================================================
    wire [79:0] msg_flat, msg_hex;
    wire [13:0] mv_dbg;
    wire        adc_ack;

    bin_to_ascii #(
        .SCALE_NUM   (SCALE_NUM),
        .SCALE_SHIFT (SCALE_SHIFT)
    ) u_conv (
        .adc_code (adc_lat),
        .ack_ok   (adc_ack),
        .mv_out   (mv_dbg),
        .msg_flat (msg_flat),
        .msg_hex  (msg_hex)
    );

    //=========================================================================
    // FSM maestra de secuenciamiento (ADC -> 10 bytes -> UART)
    //=========================================================================
    localparam [2:0] T_IDLE = 3'd0,
                     T_CONV = 3'd1,
                     T_LOAD = 3'd2,
                     T_PUSH = 3'd3,
                     T_WAIT = 3'd4;

    reg [2:0] tstate;
    reg [3:0] idx;          // 0..9

    always @(posedge clk50 or negedge rst_n_s) begin
        if (!rst_n_s) begin
            tstate <= T_IDLE;
            idx    <= 4'd0;
        end else begin
            case (tstate)
                T_IDLE : if (tick)      tstate <= T_CONV;
                T_CONV : if (adc_valid) tstate <= T_LOAD;
                T_LOAD : begin idx <= 4'd0; tstate <= T_PUSH; end
                T_PUSH :                tstate <= T_WAIT;   // dura 1 ciclo
                T_WAIT : if (tx_done) begin
                             if (idx == 4'd9) tstate <= T_IDLE;
                             else begin idx <= idx + 1'b1; tstate <= T_PUSH; end
                         end
                default:                tstate <= T_IDLE;
            endcase
        end
    end

    assign adc_start = (tstate == T_IDLE) && tick;
    wire       tx_start = (tstate == T_PUSH);          // pulso de 1 ciclo
    wire [79:0] msg_sel = DIAG_I2C ? msg_hex : msg_flat;
    wire [7:0]  tx_byte = msg_sel[8*idx +: 8];

    //=========================================================================
    // Transmisor UART
    //=========================================================================
    wire tx_busy, tx_done;

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD     (BAUD)
    ) u_uart (
        .clk      (clk50),
        .rst_n    (rst_n_s),
        .tx_start (tx_start),
        .data_in  (tx_byte),
        .tx_o     (uart_txd),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    assign led_busy = ~tx_busy;   // LEDs de la Core EP4CE6 son activos en bajo

endmodule
