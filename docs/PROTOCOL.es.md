<div align="right"><a href="PROTOCOL.md">🇬🇧 English</a> · <a href="PROTOCOL.es.md">🇪🇸 Español</a></div>

# Protocolo de cable del monitor (v2, enmarcado) — Amiga ChipLab

[← Volver al README](../README.es.md)

Referencia para escribir otro cliente (la implementación Pharo es `GT4AmigaMonitorClient`, la del Amiga `amiga/s/gt4amiga-monitor.s` — ambas llevan toda la historia de diseño en sus comentarios). El protocolo es byte a byte idéntico sobre ambos transportes (`SER:` bajo FS-UAE, TCP en hardware real). Todos los valores multibyte son **big-endian** (nativo del 68k).

**Trama de comando** (host → Amiga):

```
[$A5] [opcode] [payload…] [chk]     chk = XOR del opcode y de cada byte de payload
```

**Trama de respuesta** (Amiga → host):

```
[$5A] [status] [payload…] [chk]     chk = XOR del status y de cada byte de payload
```

`status 0` = OK, ejecutado; sigue el payload. `status 1` = **NAK**: el checksum no cuadró y **no se ejecutó nada** — siempre seguro de reenviar, incluso un CALL o un EXEC. Una trama NAK no lleva payload (`[$5A][$01][$01]`).

**Comandos** (los opcodes son las letras ASCII):

| Op | Payload | Payload de respuesta OK |
|----|---------|-------------------------|
| `R` `$52` leer memoria | `[size:1][pad:1][addr:4]` — size 1, 2 o 4 | los `size` bytes leídos |
| `W` `$57` escribir memoria | `[size:1][pad:1][addr:4][data × size]` | vacío (ack) |
| `B` `$42` lectura por bloque | `[addr:4][len:2]` — len 1..4096 | los `len` bytes leídos |
| `P` `$50` escritura por bloque | `[addr:4][len:2][data × len]` — len 1..4096 | vacío (ack) |
| `C` `$43` llamar librería | `[lib:1][pad:1][lvo:2 con signo][a0:4][a1:4][d0:4][d1:4][d2:4][d3:4]` | `d0` tras la llamada (4 bytes) |
| `S` `$53` puntero a pantalla | ninguno | `IntuitionBase->FirstScreen` (4 bytes) |
| `X` `$58` ejecutar programa | ninguno | dirección del mailbox de ejecución (4 bytes), o `0` si no se lanzó nada |
| `Q` `$51` salir | ninguno | vacío; el monitor sale a continuación |

`lib` para CALL: `0` = exec, `1` = dos.library, `2` = intuition.library, `3` = graphics.library (las bases se abren una vez al arrancar el monitor). `lvo` es el offset del vector de librería, entero de 16 bits con signo (p. ej. FindTask = `-294`).

`B`/`P` llevan como mucho 4096 bytes por trama (el límite del búfer del monitor; los clientes trocean transferencias mayores). El monitor toma una instantánea de la región en un búfer interno, así que los datos y el checksum de una respuesta `B` vienen de una lectura coherente, y un `P` solo copia al destino *después* de que el checksum verifique — una trama corrupta hace NAK sin haber tocado memoria. Ambos copian byte a byte: son para RAM (framebuffers, copper lists, sprites); los registros del chip custom requieren accesos de tamaño word — usa `R`/`W` para esos.

`X` carga `GT4A:incoming/program` y lo ejecuta como un proceso de AmigaDOS separado con su `Output()` capturado a `GT4A:outgoing/output`; el monitor sigue sirviendo comandos entretanto. La finalización se sondea desde el host con lecturas `R` normales del mailbox: byte de estado en `+0` (`0` nunca corrió, `1` corriendo, `2` terminado, `3` error de lanzamiento), long de código de retorno en `+4` (el `d0` final del programa, válido en estado 2). Un `X` con estado `1`, o cuyo `LoadSeg`/`CreateProc` falla, responde `0`.

**Reglas de reintento** (lo que implementa el cliente Pharo, y lo que debería cualquier cliente):

- **NAK** → reenvía, siempre. Nada corrió en el lado Amiga.
- **Silencio o respuesta corrupta** → la ejecución es *incierta*: el comando pudo haberse ejecutado y solo perderse su respuesta. Reintenta solo los comandos idempotentes — `R`, `W`, `S` — y nunca `C` ni `X` (una llamada a librería o un lanzamiento de programa podrían ejecutarse dos veces).
- Una ronda de reintento completamente silenciosa suele significar que la conexión en sí está muerta (p. ej. el peer cerró y el socket quedó en CLOSE-WAIT): fuerza una reconexión y prueba una vez más.

**Resincronización**: el parser del monitor *caza* el byte de sincronía `$A5` — tras cualquier trama mutilada descarta bytes hasta el siguiente `$A5`, así que se recupera solo; un `$A5` dentro de un payload es inofensivo en operación normal porque los cuerpos de trama se leen por longitud, no escaneando. Un `W` cuyo byte de `size` no es 1, 2 o 4 se descarta de plano (realinea, sin NAK) — un size corrupto nunca debe convertirse en una cuenta de lectura. En el cable, la capa serie debe estar libre de control de flujo XON/XOFF, o los bytes de payload `$11`/`$13` se los come el transporte — ver la nota de configuración serie de una sola vez en [SETUP.es.md](SETUP.es.md).
