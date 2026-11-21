# Changelog

Cambios de este repositorio. El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
La evolución del **proyecto** (etapas de diseño, prototipos y pruebas) está en
[docs/progreso.md](docs/progreso.md).

## [1.1.0] - 2026-11-20

### Añadido
- Código del diseño final en `src/`: `top.v`, `orientacion.v`, `i2c_master.v`, `top_telemetry.v`,
  `ads1115_reader.v`, `bin_to_ascii.v` y `uart_tx.v`.
- Banco de pruebas `top_tb.v` y modelo del ADS1115 `slave_model_inc.v`.
- Proyecto de Quartus (`top.qpf`, `top.qsf`, `top.sdc`) y `Makefile` del curso.
- `src/NOTAS_PUESTA_EN_MARCHA.md`: guía de montaje y depuración.

### Cambiado
- `src/` reúne todo el proyecto en una sola carpeta, como lo esperan `top.qsf` y el `Makefile`.
  Se eliminaron las carpetas de relleno `src/rtl`, `src/caracterizacion`, `sim` y `constraints`.
- README: instrucciones reales de compilación y simulación; insignia de estado corregida.

## [1.0.0] - 2026-11-19

Primera publicación del repositorio con la documentación del proyecto entregado el 2026-07-28.

### Añadido
- Estructura de carpetas: `src/rtl`, `src/caracterizacion`, `sim`, `constraints`, `hardware`, `docs`.
- Informe final en PDF y las ocho figuras raster extraídas de él.
- `docs/arquitectura.md`: arquitectura y diseño de los bloques I2C, orientación, PWM y UART.
- `hardware/README.md`: materiales, esquemático, pines y montaje mecánico.
- `docs/resultados.md`: verificación, prueba del sistema, limitaciones y conclusiones.
- `docs/progreso.md`: bitácora de etapas y problemas resueltos.
- `README.md` principal.
