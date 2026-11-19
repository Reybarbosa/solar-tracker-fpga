# Restricciones de Quartus

> **Estado:** archivos pendientes de subir.

| Archivo   | Contenido |
|-----------|-----------|
| `top.qsf` | Entidad superior (`top`), asignación de pines (estándar 3.3-V LVTTL) y `RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"`. |
| `top.sdc` | Reloj de 20 ns de periodo (50 MHz). |

La tabla de pines está en [hardware/README.md](../hardware/README.md#asignación-de-pines).

**Por qué `AS INPUT TRI-STATED`:** por defecto Quartus deja los pines no usados como salidas a
masa, lo que puede provocar cortocircuitos contra lo que esté conectado en la tarjeta de expansión.
