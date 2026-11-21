// =============================================================================
// Modulo: i2c_master.v
// Controlador I2C robusto a 100 kHz
// =============================================================================

module i2c_master (
    input  wire       clk,        // Reloj de 50 MHz
    input  wire       rst_n,      // Reset activo en bajo
    
    input  wire       execute,    // Iniciar transmision
    input  wire       is_read,    // 0: Escribir, 1: Leer
    input  wire       gen_start,  // 1: Generar START
    input  wire       gen_stop,   // 1: Generar STOP
    input  wire [7:0] din,        // Dato a transmitir
    input  wire       ack_in,     // ACK a enviar en lectura (0=ACK, 1=NACK)
    
    output reg  [7:0] dout,       // Dato recibido
    output reg        rx_ack,     // ACK recibido del esclavo (0=ACK, 1=NACK)
    output reg        busy,       // 1: Master ocupado
    
    inout  wire       scl,
    inout  wire       sda
);

    // Divisor de reloj: 50 MHz / 500 = 100 kHz (4 ticks por ciclo I2C)
    reg [6:0] tick_cnt = 0;
    reg       tick = 0;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            tick_cnt <= 0;
            tick     <= 0;
        end else if (tick_cnt == 7'd124) begin
            tick_cnt <= 0;
            tick     <= 1'b1;
        end else begin
            tick_cnt <= tick_cnt + 1'b1;
            tick     <= 1'b0;
        end
    end

    // Controladores Open-Drain
    reg scl_out = 1'b1;
    reg sda_out = 1'b1;
    assign scl = scl_out ? 1'bz : 1'b0;
    assign sda = sda_out ? 1'bz : 1'b0;

    localparam IDLE  = 0, START1 = 1, START2 = 2, 
               BIT0  = 3, BIT1   = 4, BIT2   = 5, BIT3 = 6,
               ACK0  = 7, ACK1   = 8, ACK2   = 9, ACK3 = 10,
               STOP1 = 11, STOP2  = 12, STOP3 = 13;

    reg [3:0] state = IDLE;
    reg [2:0] bit_idx = 0;
    reg [7:0] tx_shift = 0;
    reg [7:0] rx_shift = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= IDLE;
            busy     <= 0;
            scl_out  <= 1'b1;
            sda_out  <= 1'b1;
            dout     <= 8'h00;
            rx_ack   <= 1'b0;
        end else if (tick) begin
            case (state)
                IDLE: begin
                    if (execute) begin
                        busy     <= 1'b1;
                        tx_shift <= din;
                        bit_idx  <= 3'd7;
                        if (gen_start) state <= START1;
                        else           state <= BIT0;
                    end else begin
                        busy <= 1'b0;
                    end
                end
                
                // Generacion de START
                START1: begin sda_out <= 1'b0; scl_out <= 1'b1; state <= START2; end
                START2: begin sda_out <= 1'b0; scl_out <= 1'b0; state <= BIT0; end
                
                // Transmision / Recepcion de Bits
                BIT0: begin scl_out <= 1'b0; sda_out <= is_read ? 1'b1 : tx_shift[bit_idx]; state <= BIT1; end
                BIT1: begin scl_out <= 1'b1; state <= BIT2; end
                BIT2: begin scl_out <= 1'b1; rx_shift[bit_idx] <= sda; state <= BIT3; end
                BIT3: begin 
                    scl_out <= 1'b0; 
                    if (bit_idx == 0) state <= ACK0;
                    else begin bit_idx <= bit_idx - 1'b1; state <= BIT0; end
                end
                
                // Fase de ACK
                ACK0: begin scl_out <= 1'b0; sda_out <= is_read ? ack_in : 1'b1; state <= ACK1; end
                ACK1: begin scl_out <= 1'b1; state <= ACK2; end
                ACK2: begin scl_out <= 1'b1; rx_ack <= sda; dout <= rx_shift; state <= ACK3; end
                ACK3: begin 
                    scl_out <= 1'b0; 
                    sda_out <= 1'b1; 
                    if (gen_stop) state <= STOP1;
                    else          state <= IDLE;
                end
                
                // Generacion de STOP
                STOP1: begin scl_out <= 1'b0; sda_out <= 1'b0; state <= STOP2; end
                STOP2: begin scl_out <= 1'b1; sda_out <= 1'b0; state <= STOP3; end
                STOP3: begin scl_out <= 1'b1; sda_out <= 1'b1; state <= IDLE; end
            endcase
        end
    end
endmodule
