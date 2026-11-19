# Simulación

> **Estado:** archivos pendientes de subir.

| Archivo             | Función |
|---------------------|---------|
| `top_tb.v`          | Banco de pruebas del diseño completo (no sintetizable). Instancia dos modelos de esclavo ADS1115, uno por cada bus, y decodifica la línea serial para imprimir en consola la cadena transmitida. |
| `slave_model_inc.v` | Modelo de simulación del esclavo ADS1115. |

Los parámetros que se comprobaron con este banco de pruebas están en
[docs/resultados.md](../docs/resultados.md#verificación-por-simulación).
