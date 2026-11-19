# Changelog

Cambios de este repositorio. El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
La evolución del **proyecto** (etapas de diseño, prototipos y pruebas) está en
[docs/progreso.md](docs/progreso.md).

## [Sin publicar]

### Pendiente
- Código Verilog del diseño completo y de la etapa de caracterización.
- Banco de pruebas y modelo del esclavo ADS1115.
- Archivos de restricciones `top.qsf` y `top.sdc`.

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
