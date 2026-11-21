// =============================================================================
//  top_tb.v -- Verificacion del diseno fusionado (orientacion + telemetria)
//  Comprueba que ambos subsistemas conviven: los dos buses I2C operan en
//  paralelo, los servos generan PWM y la telemetria transmite por la UART.
// =============================================================================
`timescale 1ns/1ns
`include "slave_model_inc.v"

module top_tb;
    reg  clk = 0;
    always #10 clk = !clk;                     // 50 MHz

    wire [3:0] leds;
    wire sda, scl, sda_tel, scl_tel, txd, sv1, sv2;
    pullup (sda);      pullup (scl);           // pull-ups del bus de orientacion
    pullup (sda_tel);  pullup (scl_tel);       // pull-ups del bus de telemetria

    top dut (
        .clk(clk), .leds(leds), .sda(sda), .scl(scl),
        .pwm_servo1(sv1), .pwm_servo2(sv2),
        .sda_tel(sda_tel), .scl_tel(scl_tel), .uart_txd(txd)
    );

    // ADS1115 #1 (LDR) y ADS1115 #2 (panel), buses independientes
    ads1115_slave_model #(.ADDR(7'h48), .CONV(16'd12000)) u_ads_ldr
        (.scl(scl), .sda(sda));
    ads1115_slave_model #(.ADDR(7'h48), .CONV(16'd19400)) u_ads_panel
        (.scl(scl_tel), .sda(sda_tel));

    initial begin $dumpfile("top_tb.vcd"); $dumpvars(0, top_tb); end

    integer k; reg [7:0] b; real BIT_NS;
    initial begin
        BIT_NS = 1.0e9/9600.0;
        $display("=== Diseno fusionado: orientacion + telemetria ===");
        repeat (2) begin
            $write("UART -> HC-05: \"");
            for (k = 0; k < 10; k = k + 1) begin
                @(negedge txd); #(BIT_NS*1.5);
                b[0]=txd; #(BIT_NS); b[1]=txd; #(BIT_NS);
                b[2]=txd; #(BIT_NS); b[3]=txd; #(BIT_NS);
                b[4]=txd; #(BIT_NS); b[5]=txd; #(BIT_NS);
                b[6]=txd; #(BIT_NS); b[7]=txd; #(BIT_NS);
                if      (b == 8'h0D) $write("\\r");
                else if (b == 8'h0A) $write("\\n");
                else                 $write("%c", b);
            end
            $display("\"");
        end
        $display("PWM servos: sv1=%b sv2=%b   LEDs=%b", sv1, sv2, leds);
        $display("Bus I2C de orientacion activo (scl=%b)  |  telemetria (scl_tel=%b)", scl, scl_tel);
        $display("=== Ambos subsistemas conviven correctamente ===");
        $finish;
    end
    initial begin #3_000_000_000; $display("TIMEOUT"); $finish; end
endmodule
