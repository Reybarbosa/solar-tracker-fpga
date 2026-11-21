// =============================================================================
//  top.v -- Seguidor Solar de 2 Ejes con Telemetria Bluetooth
//  Nivel superior del diseno fusionado.
//
//  Tarjeta : Core EP4CE6 / DVK601   (Cyclone IV E, ver DEVICE en top.qsf)
//  Reloj   : 50 MHz  (PIN_23, periodo de 20 ns declarado en top.sdc)
//
//  Este modulo NO contiene logica de control: solo instancia los dos
//  subsistemas y genera el reset de arranque comun.
//
//    orientacion     -> lazo de seguimiento: escanea los 4 LDR por I2C,
//                       calcula el error diferencial y mueve los 2 servos.
//                       Bus I2C propio: sda / scl        (PIN_55 / PIN_54)
//
//    top_telemetry   -> mide la tension del panel con un segundo ADS1115,
//                       la convierte a la cadena ASCII "V: x.xxV\r\n" y la
//                       transmite por UART a 9600 bps hacia el HC-05.
//                       Bus I2C propio: sda_tel / scl_tel (PIN_52 / PIN_51)
//
//  POR QUE DOS BUSES I2C SEPARADOS
//  -------------------------------
//  Los dos ADS1115 tienen el pin ADDR a masa, asi que ambos responden a la
//  misma direccion 0x48. Dos esclavos con la misma direccion no pueden
//  convivir en un mismo bus. Al darle un bus propio a cada uno, ademas, el
//  lazo de seguimiento y el envio de telemetria quedan desacoplados: ninguno
//  tiene que esperar al otro para acceder al bus.
// =============================================================================
`timescale 1ns/1ps

module top (
    input  wire       clk,         // PIN_23  oscilador de 50 MHz

    // ---- Subsistema de orientacion ----------------------------------------
    output wire [3:0] leds,        // PIN_3, PIN_7, PIN_10, PIN_11 (activos en bajo)
    inout  wire       sda,         // PIN_55  ADS1115 de los LDR (datos)
    inout  wire       scl,         // PIN_54  ADS1115 de los LDR (reloj)
    output wire       pwm_servo1,  // PIN_59  servo horizontal (base)
    output wire       pwm_servo2,  // PIN_60  servo vertical  (cabeza)

    // ---- Subsistema de telemetria -----------------------------------------
    inout  wire       sda_tel,     // PIN_52  ADS1115 del panel (datos)
    inout  wire       scl_tel,     // PIN_51  ADS1115 del panel (reloj)
    output wire       uart_txd     // PIN_64  hacia el pin RXD del HC-05
);

    // =========================================================================
    //  RESET DE ARRANQUE (power-on reset)
    //
    //  El contador arranca en cero tras la configuracion de la FPGA, cuenta
    //  hasta 0xFFFF y alli se detiene, manteniendo rst_n en bajo durante
    //      2^16 / 50 MHz = 1.31 ms
    //
    //  Ese intervalo da tiempo a que las resistencias de pull-up lleven SDA y
    //  SCL a nivel alto y a que los ADS1115 terminen su propio arranque antes
    //  de la primera transaccion. Sin este retardo la primera lectura salia
    //  erratica.
    // =========================================================================
    reg  [15:0] rst_cnt = 16'd0;
    wire        rst_n   = (rst_cnt == 16'hFFFF);

    always @(posedge clk) begin
        if (!rst_n) rst_cnt <= rst_cnt + 1'b1;
    end

    // =========================================================================
    //  SUBSISTEMA 1: ORIENTACION
    //
    //  Genera su propio reset interno, por eso no recibe rst_n desde aqui.
    // =========================================================================
    orientacion u_orientacion (
        .clk        (clk),
        .leds       (leds),
        .sda        (sda),
        .scl        (scl),
        .pwm_servo1 (pwm_servo1),
        .pwm_servo2 (pwm_servo2)
    );

    // =========================================================================
    //  SUBSISTEMA 2: TELEMETRIA POR BLUETOOTH
    //
    //  USE_STUB = 0 -> usa el maestro I2C real (ads1115_reader) contra el
    //                  ADS1115 del panel. Con USE_STUB = 1 el modulo genera
    //                  una rampa de prueba interna y NO toca el bus I2C; eso
    //                  solo sirve para probar el enlace UART/Bluetooth sin el
    //                  ADC montado.
    //
    //  SCALE_NUM = 1, SCALE_SHIFT = 2 -> escalado para divisor 10k/10k
    //                  (k = 1/2) con el PGA en +/-4.096 V:
    //                      mV_panel = codigo_ADC / 4
    //
    //  DIAG_I2C = 0  -> transmite voltios en texto. Ponerlo en 1 hace que
    //                  transmita "R=XXXX A" (codigo crudo en hex + bandera de
    //                  ACK), util para depurar el bus si el HC-05 no muestra
    //                  cifras coherentes.
    // =========================================================================
    wire led_busy;   // parpadeo durante la transmision; no se lleva a ningun pin

    top_telemetry #(
        .CLK_FREQ    (50_000_000),
        .BAUD        (9600),
        .PERIOD_MS   (500),        // una muestra cada medio segundo
        .SCALE_NUM   (1),
        .SCALE_SHIFT (2),
        .USE_STUB    (1'b0),       // <-- ADC real, no la rampa de prueba
        .DIAG_I2C    (1'b0)
    ) u_telemetry (
        .clk50    (clk),
        .rst_n    (rst_n),
        .i2c_scl  (scl_tel),
        .i2c_sda  (sda_tel),
        .uart_txd (uart_txd),
        .led_busy (led_busy)
    );

endmodule
