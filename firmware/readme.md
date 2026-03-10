# Firmware

Este directorio contiene firmware para STM32 (Bluepill / F103) usado con el proyecto Flutter.

## Carpetas

- `stm32_single_motor_legacy/`: firmware inicial de 1 motor con comandos por caracteres (legacy).
- `stm32_4motors_ble_uart/`: firmware nuevo compatible con la app (comandos por línea `M1:10`, `PID:...`).

## Nota
El firmware legacy tenía un conflicto: el comando `'D'` estaba duplicado (una vez para mover -2 y otra para Kd+). En la versión legacy del repo lo dejamos tal cual para referencia, pero en la versión nueva se usa protocolo por líneas.