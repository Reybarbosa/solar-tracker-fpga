# Código fuente (Verilog)

> **Estado:** los archivos `.v` todavía no se han subido al repositorio. Esta carpeta ya tiene la
> estructura donde van, según la jerarquía de módulos documentada en el informe
> ([Tabla 1](../docs/arquitectura.md#jerarquía-de-módulos)).

## `rtl/` — diseño completo (seguidor + telemetría)

| Archivo              | Nivel       | Función |
|----------------------|-------------|---------|
| `top.v`              | Superior    | Instancia los dos subsistemas y genera el reset de arranque. Es la entidad superior declarada en `top.qsf`. |
| `orientacion.v`      | Sub-nivel 1 | Lazo de seguimiento: escáner I2C de cuatro canales, lógica diferencial, PWM de ambos ejes e indicación por LED. |
| `i2c_master.v`       | Sub-nivel 2 | Maestro I2C a 100 kHz orientado a byte, usado por `orientacion`. |
| `top_telemetry.v`    | Sub-nivel 1 | Secuenciador de telemetría: dispara la medida, arma la trama y la entrega a la UART. |
| `ads1115_reader.v`   | Sub-nivel 2 | Maestro I2C propio más el secuenciador de la transacción completa del ADS1115. |
| `bin_to_ascii.v`     | Sub-nivel 2 | Conversión combinacional del código del ADC a la cadena ASCII de la trama. |
| `uart_tx.v`          | Sub-nivel 2 | Transmisor UART 8N1 a 9 600 baudios. |

## `caracterizacion/` — etapa previa de control manual

| Archivo                 | Función |
|-------------------------|---------|
| `top.v`                 | `top.v` de caracterización manual (Figura 5 del informe). Mueve los ejes con los pulsadores `up`, `down`, `left`, `right` y `press`. No lee sensores ni transmite nada. |
| `control_dos_servos.v`  | Traduce las pulsaciones en consignas de 17 bits (`pulso_servo1`, `pulso_servo2`). |
| `pwm_servo.v`           | Generador PWM de un servo (instanciado dos veces). |

El proyecto tiene **dos** archivos `top.v`, de dos etapas distintas del desarrollo; por eso van en
carpetas separadas.

## Verificación y restricciones

- [`../sim/`](../sim/) → `top_tb.v` (banco de pruebas) y `slave_model_inc.v` (modelo del esclavo ADS1115).
- [`../constraints/`](../constraints/) → `top.qsf` (pines) y `top.sdc` (reloj de 50 MHz).

## Fragmento incluido en el informe

El único fragmento de código reproducido en el informe es la generación de PWM de los dos ejes
dentro de `orientacion.v` (Listing 1). Se copia aquí como referencia hasta que se suba el archivo
completo:

```verilog
// Contador de periodo: 20 ms @ 50 MHz
reg [19:0] pwm_cnt = 0;
always @(posedge clk) begin
    if (pwm_cnt >= 20'd999_999) pwm_cnt <= 0;
    else                        pwm_cnt <= pwm_cnt + 1'b1;
end

// Consignas de posicion, centradas al arranque (90 grados)
reg [17:0] pos_h = 18'd75000; // eje horizontal (base)
reg [17:0] pos_v = 18'd75000; // eje vertical (cabeza)

// Comparacion: un solo contador, dos salidas en fase
assign pwm_servo1 = (pwm_cnt < pos_h); // PIN_59
assign pwm_servo2 = (pwm_cnt < pos_v); // PIN_60
```
