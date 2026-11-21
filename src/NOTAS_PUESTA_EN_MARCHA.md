# Notas de puesta en marcha — Solar Tracker con telemetría Bluetooth

> **Archivo añadido al recuperar el proyecto (18-nov-2026).** No formaba parte
> de la entrega original; es solo una guía rápida para volver a montarlo.

## Qué contiene el proyecto

| Archivo | Síntesis | Función |
|---|:---:|---|
| `top.v` | sí | Nivel superior. Instancia los dos subsistemas y genera el reset de arranque. |
| `orientacion.v` | sí | Lazo de seguimiento: escanea los 4 LDR por I²C, calcula el error diferencial y mueve los 2 servos. |
| `i2c_master.v` | sí | Maestro I²C a 100 kHz usado por `orientacion`. |
| `top_telemetry.v` | sí | Secuenciador de telemetría: dispara la medida, arma la trama y la entrega a la UART. |
| `ads1115_reader.v` | sí | Maestro I²C + secuenciador completo del ADS1115 del panel. |
| `bin_to_ascii.v` | sí | Convierte el código del ADC a la cadena `"V: x.xxV\r\n"`. |
| `uart_tx.v` | sí | Transmisor UART 8N1 a 9600 bps. |
| `top_tb.v` | no | Banco de pruebas del diseño fusionado. |
| `slave_model_inc.v` | no | Modelo de simulación del ADS1115. |

## Conexiones (según `top.qsf`)

| Señal | Pin | Va a |
|---|---|---|
| `clk` | PIN_23 | Oscilador de 50 MHz |
| `leds[0..3]` | PIN_3, 7, 10, 11 | LEDs de la Core (activos en bajo) |
| `scl` / `sda` | PIN_54 / PIN_55 | **ADS1115 de los LDR** |
| `pwm_servo1` | PIN_59 | Servo horizontal (base) |
| `pwm_servo2` | PIN_60 | Servo vertical (cabeza) |
| `scl_tel` / `sda_tel` | PIN_51 / PIN_52 | **ADS1115 del panel** |
| `uart_txd` | PIN_64 | **Pin RXD del HC-05** |

Los dos buses I²C necesitan sus propias resistencias de pull-up de 4.7 kΩ a 3.3 V.

**Los dos ADS1115 tienen ADDR a masa**, así que ambos responden a la dirección
0x48. Por eso van en buses separados: dos esclavos con la misma dirección no
pueden convivir en un mismo bus.

## Telemetría Bluetooth

- El HC-05 va en modo esclavo, **9600 baudios**, y solo se usa su pin **RXD**
  (la FPGA transmite, no recibe).
- Lo que se transmite es **únicamente la tensión del panel**, cada 500 ms, como
  texto plano: `V: 4.85V` + CR + LF.
- Al ser texto ASCII, sirve **cualquier terminal Bluetooth serial** del celular
  o la tablet. No hace falta una app especial: se empareja con el HC-05
  (clave típica `1234` o `0000`) y se abre el terminal.

### Si el celular no muestra cifras coherentes

En `top.v`, dentro de la instancia `u_telemetry`, cambia `DIAG_I2C` a `1'b1`:

```verilog
.DIAG_I2C (1'b1)      // en vez de 1'b0
```

Entonces transmite `R=XXXX A` — el código crudo del ADC en hexadecimal y la
bandera de ACK. Si el último carácter es `0`, el ADS1115 no está contestando en
el bus: revisa pull-ups, alimentación y cableado antes de buscar el problema en
el código.

### Si quieres probar el enlace sin el ADC del panel conectado

Cambia `USE_STUB` a `1'b1`. El módulo genera entonces una rampa interna
(0.00 → 0.66 → 1.32 … V) y **no toca el bus I²C**. Sirve para confirmar que el
HC-05 y el celular están bien antes de pelearse con el ADC.
**Acuérdate de volver a dejarlo en `1'b0` para la entrega**, o estarás
mostrando números inventados en vez de la tensión real del panel.

## Comandos

```bash
make sim     # simulación (debe imprimir  V: 4.85V)
make rtl     # diagrama RTL
make syn     # síntesis en Quartus
make config  # configurar la FPGA
```

> ⚠️ **Cuidado con `make sim`: genera un archivo de ondas de ~8.7 GB.**
>
> El testbench simula más de 1 segundo de tiempo real con el reloj a 50 MHz, y
> la línea `$dumpvars(0, top_tb)` vuelca **todas** las señales de la jerarquía.
> El resultado es `sim/top_tb.vcd` con casi 9 GB. La simulación funciona bien
> —el resultado en consola es correcto— pero si tienes poco espacio libre te
> llena el disco.
>
> Si solo te interesa el texto de la consola, comenta esa línea en `top_tb.v`:
>
> ```verilog
> // initial begin $dumpfile("top_tb.vcd"); $dumpvars(0, top_tb); end
> ```
>
> Si necesitas ver las ondas en GTKWave, limita el volcado a lo que te importa:
>
> ```verilog
> initial begin
>     $dumpfile("top_tb.vcd");
>     $dumpvars(1, top_tb);              // solo el nivel superior
>     $dumpvars(1, top_tb.dut.u_telemetry);   // y la telemetría
> end
> ```
>
> Acuérdate de borrar `sim/` (`make clean-sim`) después de simular.

La simulación es la prueba de que todo está bien: el modelo de esclavo entrega
el código 19400, y 19400 / 4 = 4850 mV, así que en consola debe salir
exactamente `V: 4.85V`.

## Comportamiento esperado al encender

1. **~1.3 ms**: reset de arranque, se estabilizan los buses I²C.
2. **2 segundos**: los LEDs parpadean los cuatro a la vez y los servos quedan
   centrados (90°) mientras se estabilizan las lecturas del ADC.
3. **Después**: empieza el seguimiento. Los LEDs pasan a indicar de qué lado
   hay más luz (izquierda, derecha, arriba, abajo) y la tablet recibe una
   lectura de tensión cada medio segundo.

Si los servos se mueven pero **en sentido contrario**, el cableado de los LDR
está intercambiado respecto al mapeo del código: `AIN0`/`AIN1` son los dos
sensores de **abajo** y `AIN2`/`AIN3` los de **arriba**.

## Un punto a revisar antes de entregar

`top.qsf` declara `DEVICE EP4CE10E22C8`, pero la cabecera de `top_telemetry.v`
menciona EP4CE6E22C8 y la tarjeta se llama openep4ce6-c. Confirma cuál chip
tiene físicamente tu Core y deja el dato unificado, porque si el profesor abre
el `.qsf` va a ver la inconsistencia.
