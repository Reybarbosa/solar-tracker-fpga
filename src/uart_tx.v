
`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_FREQ = 50_000_000,   // Hz del oscilador de la tarjeta
    parameter integer BAUD     = 9600          // bps
)(
    input  wire       clk,        // 50 MHz
    input  wire       rst_n,      // reset asincrono activo en bajo
    input  wire       tx_start,   // pulso de 1 ciclo: inicia la trama
    input  wire [7:0] data_in,    // byte a transmitir (muestreado en S_IDLE)
    output reg        tx_o,       // linea serie hacia HC-05 RXD
    output wire       tx_busy,    // 1 mientras la trama esta en curso
    output wire       tx_done     // pulso de 1 ciclo al terminar el bit de stop
);

    
    // BAUD_DIV = 50_000_000 / 9600 = 5208 (trunca)
    // Baudio real = 50e6/5208 = 9600.61 bps  -> error = +0.0064 %  (limite: 2 %)
    localparam integer BAUD_DIV = CLK_FREQ / BAUD;
    localparam integer CW       = 13;          // ceil(log2(5208)) = 13 bits

  
    localparam [1:0] S_IDLE  = 2'b00,
                     S_START = 2'b01,
                     S_DATA  = 2'b11,
                     S_STOP  = 2'b10;

    //-------------------------------------------------------------------------
    // Registros de estado y de camino de datos
    //-------------------------------------------------------------------------
    reg  [1:0]    state, next_state;
    reg  [CW-1:0] baud_cnt;
    reg  [2:0]    bit_cnt;      // 0..7
    reg  [7:0]    shift_reg;
    reg           baud_clr;     // salida Moore de S_IDLE
    wire          baud_tick;    // bandera de fin de tiempo de bit

   
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                      baud_cnt <= {CW{1'b0}};
        else if (baud_clr || baud_tick)  baud_cnt <= {CW{1'b0}};
        else                             baud_cnt <= baud_cnt + 1'b1;
    end

    assign baud_tick = (baud_cnt == BAUD_DIV[CW-1:0] - 1'b1);

    //=========================================================================
    // 2) REGISTRO DE ESTADO
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    //=========================================================================
    // 3) LOGICA DE PROXIMO ESTADO  <-- ROMBOS DE DECISION DEL ASM
    //=========================================================================
    always @(*) begin
        next_state = state;                       // por defecto: permanecer
        case (state)
            S_IDLE : if (tx_start)                        next_state = S_START;
            S_START: if (baud_tick)                       next_state = S_DATA;
            S_DATA : if (baud_tick && (bit_cnt == 3'd7))  next_state = S_STOP;
            S_STOP : if (baud_tick)                       next_state = S_IDLE;
            default:                                      next_state = S_IDLE;
        endcase
    end

   
    always @(*) begin
        baud_clr = 1'b0;
        case (state)
            S_IDLE : begin tx_o = 1'b1;           baud_clr = 1'b1; end
            S_START: begin tx_o = 1'b0;                            end
            S_DATA : begin tx_o = shift_reg[0];                    end
            S_STOP : begin tx_o = 1'b1;                            end
            default: begin tx_o = 1'b1;                            end
        endcase
    end

    assign tx_busy = (state != S_IDLE);           // salida Moore

    
    assign tx_done = (state == S_STOP) && baud_tick;

  
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'hFF;
            bit_cnt   <= 3'd0;
        end else begin
            case (state)
                S_IDLE : if (tx_start) begin              // ovalo del bloque #1
                             shift_reg <= data_in;
                             bit_cnt   <= 3'd0;
                         end
                S_DATA : if (baud_tick) begin             // ovalos del bloque #3
                             shift_reg <= {1'b0, shift_reg[7:1]};
                             if (bit_cnt != 3'd7)
                                 bit_cnt <= bit_cnt + 1'b1;
                         end
                default: ;                                // sin transferencias
            endcase
        end
    end

endmodule
