# Código fuente y proyecto de Quartus

Todos los archivos están en la misma carpeta porque así los esperan `top.qsf` (lista de archivos
Verilog) y el `Makefile` del curso.

## Diseño (sintetizable)

| Archivo | Función |
|---------|---------|
| [`top.v`](top.v) | Nivel superior. Instancia `orientacion` y `top_telemetry` y genera el reset de arranque. |
| [`orientacion.v`](orientacion.v) | Lazo de seguimiento: escanea los 4 LDR por I2C, calcula el error diferencial, genera el PWM de los dos servos y maneja los LEDs. |
| [`i2c_master.v`](i2c_master.v) | Maestro I2C a 100 kHz orientado a byte, usado por `orientacion`. |
| [`top_telemetry.v`](top_telemetry.v) | Secuenciador de telemetría: dispara la medida cada 500 ms, arma la trama y la entrega a la UART. |
| [`ads1115_reader.v`](ads1115_reader.v) | Maestro I2C propio + secuenciador de la transacción completa con el ADS1115 del panel. |
| [`bin_to_ascii.v`](bin_to_ascii.v) | Convierte el código del ADC en la cadena `V: x.xxV\r\n`. |
| [`uart_tx.v`](uart_tx.v) | Transmisor UART 8N1 a 9 600 baudios. |

## Simulación

| Archivo | Función |
|---------|---------|
| [`top_tb.v`](top_tb.v) | Banco de pruebas del diseño completo. |
| [`slave_model_inc.v`](slave_model_inc.v) | Modelo del esclavo ADS1115. Entrega el código 19400, así que la consola debe mostrar `V: 4.85V` (19400 / 4 = 4850 mV). |

## Proyecto y restricciones

| Archivo | Contenido |
|---------|-----------|
| [`top.qpf`](top.qpf) | Proyecto de Quartus. |
| [`top.qsf`](top.qsf) | Dispositivo, lista de archivos, pines (3.3-V LVTTL) y pines no usados en alta impedancia. |
| [`top.sdc`](top.sdc) | Reloj de 50 MHz (periodo 20 ns). |
| [`Makefile`](Makefile) | Flujo del curso: `make sim`, `make rtl`, `make syn`, `make config`. |
| [`NOTAS_PUESTA_EN_MARCHA.md`](NOTAS_PUESTA_EN_MARCHA.md) | Conexiones, telemetría, depuración (`DIAG_I2C`, `USE_STUB`) y comportamiento al encender. |

## Parámetros útiles de `top_telemetry` (en `top.v`)

| Parámetro | Valor en `top.v` | Para qué sirve |
|-----------|------------------|----------------|
| `PERIOD_MS` | `500` | Periodo de envío de la telemetría. |
| `USE_STUB` | `1'b0` | En `1` genera una rampa interna sin usar el ADC (solo para probar el enlace Bluetooth). |
| `DIAG_I2C` | `1'b0` | En `1` transmite `R=XXXX A` (código crudo del ADC y bandera de ACK) para depurar el bus I2C. |

## Notas

- **Dispositivo:** `top.qsf` declara `EP4CE10E22C8`, mientras que la tarjeta es la Core EP4CE6 y
  algunas cabeceras mencionan `EP4CE6E22C8`. Conviene confirmar el chip de la tarjeta y unificarlo.
- **`make sim`** vuelca todas las señales y genera un `.vcd` de unos 8.7 GB. En
  [NOTAS_PUESTA_EN_MARCHA.md](NOTAS_PUESTA_EN_MARCHA.md) se explica cómo limitarlo.
- Los archivos de la etapa de caracterización manual de los servos (`control_dos_servos.v`,
  `pwm_servo.v` y su `top.v`) no están en este repositorio; el diseño final genera el PWM dentro de
  `orientacion.v`.

### Fragmento: PWM de los dos ejes en `orientacion.v`

Un solo contador de periodo alimenta las dos comparaciones, de modo que ambos servos quedan en fase:

```verilog
reg [19:0] pwm_cnt = 0; // Periodo de 20 ms @ 50 MHz
// ...
assign pwm_servo1 = (pwm_cnt < pos_h); // PIN_59
assign pwm_servo2 = (pwm_cnt < pos_v); // PIN_60
```
