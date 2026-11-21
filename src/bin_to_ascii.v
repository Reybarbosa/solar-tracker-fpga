//=============================================================================
//  bin_to_ascii.v -- Codigo binario ADS1115  ->  cadena ASCII "V: 4.85V\r\n"
//
//  Cadena de 10 caracteres:
//    idx :  0    1    2    3    4    5    6    7    8     9
//    chr : 'V'  ':'  ' '  'd'  '.'  'd'  'd'  'V'  CR    LF
//
//  ESCALADO (parametrizable):
//     mV_panel = (codigo_ADC * SCALE_NUM) >> SCALE_SHIFT
//
//  Caso A -> divisor 10k/20k (k=2/3) + PGA = +/-4.096 V (LSB = 125 uV):
//     V_panel = codigo * 125uV * 1.5 = codigo * 187.5 uV = codigo * 3/16 mV
//     => SCALE_NUM = 3 , SCALE_SHIFT = 4         (exacto, sin error de redondeo)
//
//  Caso B -> divisor 10k/10k (k=1/2) + PGA = +/-4.096 V:
//     V_panel = codigo * 125uV * 2 = codigo * 0.25 mV = codigo / 4 mV
//     => SCALE_NUM = 1 , SCALE_SHIFT = 2
//
//  Modulo 100 % combinacional. Costo aprox. en Cyclone IV: ~110 LEs.
//=============================================================================
`timescale 1ns/1ps

module bin_to_ascii #(
    parameter integer SCALE_NUM   = 3,   // numerador del factor de escala
    parameter integer SCALE_SHIFT = 4    // divisor = 2^SCALE_SHIFT
)(
    input  wire [15:0] adc_code,   // codigo del ADS1115 (complemento a 2)
    input  wire        ack_ok,     // 1 = el ADS1115 contesto en el bus
    output wire [13:0] mv_out,     // milivoltios del panel (para depuracion)
    output wire [79:0] msg_flat,   // 10 bytes empacados; byte i = msg_flat[8*i +: 8]
    output wire [79:0] msg_hex     // mensaje de diagnostico: "R=XXXX A\r\n" 
);

   
    wire [14:0] code_u = adc_code[15] ? 15'd0 : adc_code[14:0];

  
    wire [19:0] prod   = code_u * SCALE_NUM;
    wire [13:0] mv_raw = prod >> SCALE_SHIFT;

    // Redondeo al centesimo de voltio mas cercano (+5 mV) y tope a 9999 mV
    wire [14:0] mv_rnd = {1'b0, mv_raw} + 15'd5;
    wire [13:0] mv_sat = (mv_rnd > 15'd9999) ? 14'd9999 : mv_rnd[13:0];

    assign mv_out = mv_raw;

   
    reg  [15:0] bcd;
    integer     i;

    always @(*) begin
        bcd = 16'd0;
        for (i = 13; i >= 0; i = i - 1) begin
            if (bcd[3:0]   >= 4'd5) bcd[3:0]   = bcd[3:0]   + 4'd3;
            if (bcd[7:4]   >= 4'd5) bcd[7:4]   = bcd[7:4]   + 4'd3;
            if (bcd[11:8]  >= 4'd5) bcd[11:8]  = bcd[11:8]  + 4'd3;
            if (bcd[15:12] >= 4'd5) bcd[15:12] = bcd[15:12] + 4'd3;
            bcd = {bcd[14:0], mv_sat[i]};
        end
    end

    wire [3:0] d_volt = bcd[15:12];   // unidades de voltio   (millar de mV)
    wire [3:0] d_dec1 = bcd[11:8];    // primer decimal       (centena de mV)
    wire [3:0] d_dec2 = bcd[7:4];     // segundo decimal      (decena  de mV)
    // bcd[3:0] = unidades de mV -> se descarta (ya se uso en el redondeo)

 
    wire [7:0] c_volt = 8'h30 + {4'd0, d_volt};
    wire [7:0] c_dec1 = 8'h30 + {4'd0, d_dec1};
    wire [7:0] c_dec2 = 8'h30 + {4'd0, d_dec2};

    assign msg_flat = { 8'h0A,    // 9 : LF
                        8'h0D,    // 8 : CR
                        8'h56,    // 7 : 'V'
                        c_dec2,   // 6 : segundo decimal
                        c_dec1,   // 5 : primer decimal
                        8'h2E,    // 4 : '.'
                        c_volt,   // 3 : unidades de voltio
                        8'h20,    // 2 : ' '
                        8'h3A,    // 1 : ':'
                        8'h56 };  // 0 : 'V'

   
    function [7:0] hexchar;
        input [3:0] n;
        begin
            hexchar = (n < 4'd10) ? (8'h30 + {4'd0,n}) : (8'h41 + {4'd0,n} - 8'd10);
        end
    endfunction

    assign msg_hex = { 8'h0A,                        // 9 : LF
                       8'h0D,                        // 8 : CR
                       (8'h30 + {7'd0, ack_ok}),     // 7 : '0' o '1'
                       8'h20,                        // 6 : ' '
                       hexchar(adc_code[3:0]),       // 5
                       hexchar(adc_code[7:4]),       // 4
                       hexchar(adc_code[11:8]),      // 3
                       hexchar(adc_code[15:12]),     // 2
                       8'h3D,                        // 1 : '='
                       8'h52 };                      // 0 : 'R'

endmodule
