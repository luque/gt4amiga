<div align="right"><a href="ROADMAP.md">🇬🇧 English</a> · <a href="ROADMAP.es.md">🇪🇸 Español</a></div>

# Roadmap — Amiga ChipLab

[← Volver al README](../README.es.md)

Amiga ChipLab es una **plataforma**: el monitor + el protocolo de cable, el cliente Pharo y el runner de FS-UAE, la integración del ensamblador, y — sobre todo — una biblioteca creciente de **modelos vivos del hardware personalizado** (registros, la máquina, y un modelo por subsistema de chip) con sus vistas vivas y páginas Lepiter de ejemplo. Los **libros** didácticos (un Hardware Reference del Amiga vivo, un libro de programación de videojuegos, un curso general de 68000) se construyen *encima* de estos modelos y viven en sus propios repositorios; este roadmap es el de la plataforma.

## Hecho

- [x] Integración del ensamblador 68000 (`vasmm68k_mot`)
- [x] Runner de FS-UAE con intercambio de ficheros por directorio compartido y captura serie
- [x] Tipo de snippet `amiga68kSnippet` a medida para páginas Lepiter
- [x] Autodetección de rutas de vasm, ROM de Kickstart y HDF de Workbench
- [x] Primeros cuadernos de ejemplo: primer del ensamblador + Hola Mundo de AmigaOS
- [x] Tomar y liberar el control del hardware (`Forbid`/`Disable`, DMA)
- [x] Bridge server (`GT4AmigaMonitorClient`): acceso vivo a memoria/llamadas a librerías sobre SER: — las cuatro primitivas verificadas de punta a punta, incluidas llamadas a `intuition.library`/`graphics.library` (`MoveScreen`, `SetRGB4`)
- [x] Cuaderno de ejemplo del bridge server: lecturas en vivo, cambio de color con `SetRGB4`, y un slider de GToolkit manejando el color de fondo en tiempo real
- [x] Cuaderno de ejemplo del split de Copper: copper list hecha a mano en chip RAM viva, slider moviendo la línea de split
- [x] Protocolo del monitor enmarcado (v2): byte de sincronía `$A5` + checksum XOR + semántica NAK/reintento, de modo que la pérdida de bytes serie es un error detectable y reintentable en vez de corrupción silenciosa de memoria; el monitor se resincroniza solo tras cualquier trama corrupta
- [x] Abstracción de transporte del monitor: servidor TCP vía `bsdsocket.library` (hardware real por la red) con alternativa `SER:` (FS-UAE), autoseleccionada al arrancar; disciplina de pila arreglada para que las salidas por pérdida de enlace sean limpias desde cualquier profundidad de llamada

### Un solo programa residente (el monitor absorbe al watcher)

Objetivo: que el monitor sea el *único* programa residente del lado Amiga, reemplazando al script watcher de sondeo. Esto elimina la contención de SER: entre watcher y monitor, la latencia de 1 segundo del sondeo del trigger, y la carrera trigger/done-marker — y el pipeline de un tiro hereda gratis la fiabilidad de checksum/reintento del protocolo enmarcado. También funciona sin cambios sobre el transporte TCP en hardware real, donde la redirección `>SER:` del watcher no existe.

- [x] Nuevo opcode `X` del monitor (ejecutar): carga `GT4A:incoming/program` con `LoadSeg()` y lo lanza como un **proceso separado** vía `CreateProc()` (dos.library V34 — presente en Kickstart 1.3), no un `jsr` en proceso. El monitor hace ack inmediatamente y vuelve a su bucle de comandos, así que `R`/`W`/`C` siguen funcionando *mientras el programa corre* — inspección en vivo de un programa en marcha desde GToolkit. **Verificado de punta a punta (2026-07-11)**: 12 `R` + 12 `S` atendidos mientras un programa de prueba de 5 segundos corría, código de retorno y salida capturada ambos correctos, relanzamiento inmediato OK. Notas de diseño:
  - Un pequeño stub corre dentro del proceso hijo: abre el fichero de captura de salida y lo instala como su propio `pr_COS` (un proceso creado por `CreateProc()` no tiene contexto CLI, así que `Output()` devolvería 0 si no), hace `jsr` al seglist cargado, y luego escribe una bandera de finalización + código de retorno en una dirección conocida antes de salir.
  - La finalización se sondea desde el host (con `R` en la dirección de la bandera) — Kickstart 1.3 no tiene notificación de muerte de proceso.
  - La salida del programa va a un fichero de captura, nunca cruda al cable.
  - Límite conocido y aceptado (ningún diseño lo elimina): un programa que toma el hardware (`Forbid`/`Disable`, DMA off) también congela el monitor — sin interrupciones no hay servicio serie/TCP. El monitor enmudece durante la ventana de toma y se recupera después gracias al enmarcado v2.
- [x] Retirar `gt4amiga-watcher`: `GT4FSUAERunner run:` ahora conduce las ejecuciones por `GT4AmigaMonitorClient` (ping `waitForMonitorTimeout:`, deploy sin trigger, `executeProgram`, espera del mailbox, `capturedOutput`)
- [x] Autoarranque del monitor al inicio vía `user-startup` (protegido por `IF EXISTS`). **Verificado (2026-07-11)**: un arranque en frío arrancó solo el monitor y `GT4FSUAERunner run:` devolvió la salida de un programa de punta a punta sin ningún watcher.
- [x] Documentar el protocolo de cable — ver [PROTOCOL.es.md](PROTOCOL.es.md).

### Modelo de hardware vivo — la materia del AHRM como objetos vivos

Objetivo: modelar la *materia* del Amiga Hardware Reference Manual como objetos vivos — **objetos de modelo con múltiples `gtViews`** que a la vez *reflejan* y *actúan sobre* el estado del chip custom a través del monitor, más **figuras vivas** (diagramas dibujados desde el estado real de la máquina, no imágenes estáticas) y páginas de ejemplo finas. Los libros que *enseñan* esta materia son repositorios separados que componen estos modelos; aquí construimos los modelos, sus vistas y cuadernos de ejemplo. (El texto del AHRM tiene copyright: su estructura de capítulos y tablas de registros sirven de esqueleto y datos de referencia, pero las explicaciones y figuras se escriben desde cero — y las figuras salen *mejor*, porque están vivas.)

- [x] Opcodes de transferencia por bloque en el monitor (`B`/`P`, hasta 4096 bytes por trama, troceado en el cliente para tamaños ilimitados). **Verificado de punta a punta (2026-07-11)** con una escritura-y-relectura de 8 KB (incluyendo bytes de payload `$A5`/`$11`/`$13`) y el cuaderno de ejemplo "Lectura en Bloque — La Pantalla de Workbench dentro del Libro", que lee por bloque los bitplanes vivos de Workbench y los compone en una imagen dentro del cuaderno (~5 KB/s por el puente serie de FS-UAE).
- [x] Paquete de modelo `GT4Amiga-Hardware`, fundado en el modelo de registro + campo de bits: 57 registros codificados como objetos (semántica `#read`/`#write`/`#setClear`/`#strobe`, campos decodificados — verificados contra `hardware/custom.i`, `dmabits.i`, `intbits.i`, `adkbits.i`). Cada registro sabe *cómo se conoce su valor actual*: directamente legible, por su contrapartida de lectura (DMACON vía DMACONR), derivado del SO (COLORxx preguntan al ColorMap del ViewPort vía `GetRGB4`), o shadow de la última escritura. **Verificado en vivo (2026-07-12)**: refresh del catálogo completo en 3,2 s, DMACONR `$03F0`, paleta derivada correctamente, VHPOSR moviéndose entre lecturas, toggle de BPLEN con relectura.
- [x] Panel de control interactivo de DMACON/INTENA (Bloc, `GT4Amiga-Hardware-UI`): conmutar bits con clic sobre el modelo de registro. Los clics solo encolan; un worker en background hace la escritura SET/CLR, relee y anuncia, y sondea cada 2 s en reposo. Los bits críticos para el enlace (INTEN, RBF, TBE, PORTS, y ahora VERTB/EXTER) se muestran pero bloqueados; BBUSY/BZERO son LEDs de solo lectura; el worker para al salir del scene graph. **Verificado en vivo (2026-07-14)**: BPLEN conmutado por el camino de clic con relectura y cero procesos huérfanos — más el cuaderno de ejemplo "El Panel de Control".
- [x] Modelo raíz `GT4AmigaMachine` + vistas globales: un diagrama de bloques clicable (68000, Agnus, Denise, Paula, CIAs, chip/slow RAM, ROM — flechas de DMA encendidas desde el DMACON vivo) y un mapa de memoria (regiones con volcados hex por ventana). Descomposiciones física y funcional como vistas alternativas. Medidores vivos de memoria libre chip/fast vía `C` a `exec/AvailMem`. **Verificado en vivo (2026-07-14)**: los medidores leen ExecBase/436 KB libres de chip, el volcado de ROM abre con el magic `$1111` de Kickstart, deshabilitar BPLEN+SPREN oscurece exactamente la flecha de Denise — más el cuaderno de ejemplo "La Máquina — Un Diagrama de Bloques Vivo".
- [x] La figura viva central del AHRM (6-9): el diagrama de time-slots de DMA por línea de barrido como elemento vivo — 227 color clocks, las asignaciones fijas de slots impares, y la ventana de fetch de bitplanes desde el DDFSTRT/DDFSTOP vivos con el orden de fetch de las figuras 6-11/6-12, hasta la cuenta de BPU viva. Esto obligó al modelo a responder *¿cómo se conoce un registro de display de solo escritura?*: BPLCON0/1/2, DDF/DIW y los módulos ahora derivan su valor de la **copper list viva** (`GfxBase->LOFlist`). **Verificado en vivo (2026-07-15)**: BPLCON0 deriva `$A200`, DDF `$3C-$D0` da 78 slots de bitplane, un toggle de BPLEN palidece todos los slots de bitplane y vuelve — más el cuaderno de ejemplo "Los Time Slots de DMA".
- [x] Una vista `Diagram` de inspector en cada registro: el diagrama de bits estilo AHRM como figura viva que a la vez refleja y, **donde el modelo dice que es seguro, escribe**. La escribibilidad la gobierna una **política de seguridad de escritura en el modelo** (`GT4AmigaChipRegister>>writeSafetyOf:`, la fuente única de verdad que comparte el Panel de Control): `#writable` (clicable), `#transient` (propiedad del copper, ámbar), `#linkCritical`/`#systemCritical` (rojo, bloqueado — una escritura viva a INTREQ o a VERTB/EXTER de INTENA puede dejar una tarea colgada), `#readOnly`, `#protocol`. **Verificado en vivo (2026-07-17)**: AUD0EN conmutado por el diagrama (`$03F0`→`$03F1`→`$03F0`) con relectura hardware; los bits bloqueados/transitorios se pintan rojo/ámbar; cero workers huérfanos.
- [ ] Reemplazar los bucles de sondeo por vista con un observador compartido, y añadir un tipo de snippet "hardware vivo" genérico (evalúa a un objeto de modelo, embebe su inspector que se refresca). Ataca directamente el modo de fallo de atasco del enlace por lectores concurrentes. Diseño: una **pasarela serie única** que posee el catálogo (`GT4AmigaChipRegisters>>observer`, un `GT4AmigaHardwareObserver`) es el único proceso que lee la máquina; las vistas declaran qué necesitan (`watch:for:` / `unwatch:`) y repintan desde caché con el anuncio — fuera de una página Lepiter cada vista se suscribe al entrar/salir del scene graph, dentro de una página un observador de página agrega las vistas de la página en una suscripción de grupo con su propio ciclo de vida y controles (pausar/reanudar/paso/cadencia). Ambos alimentan la misma pasarela, así que las vistas dentro y fuera de página nunca compiten por el socket.
  - [x] La pasarela serie compartida (`GT4AmigaHardwareObserver`): lecturas de la unión deduplicada, escrituras serializadas, un solo bucle en background, con sello de generación, se duerme cuando no se observa nada. **Verificado en vivo (2026-07-18)**: el Diagram migrado se suscribe/conmuta/desengancha limpiamente (`$03F0`→`$03F1`→`$03F0`), y 3 vistas sobre 2 registros distintos corren bajo 1 proceso lector leyendo DMACON una sola vez, cero huérfanos tras el desmontaje.
  - [x] Migración piloto: `GT4AmigaRegisterDiagramElement` ahora usa la pasarela en vez de su propio worker.
  - [ ] Migrar el resto de vistas (Panel de Control, timeline de DMA, diagrama de bloques) a la pasarela.
  - [ ] Observador de página + el tipo de snippet de hardware vivo genérico.
- [ ] Snapshot/restore del estado del chip para que cada ejemplo se limpie solo y las páginas se puedan re-ejecutar de arriba abajo.

### Modelos vivos para cada subsistema de chip (plataforma)

Cada uno = modelo + vistas + cuaderno de ejemplo. Son modelos de **plataforma** que los libros compondrán.

- [ ] **Copper**: modelo `CopperList` (ensamblar/desensamblar MOVE/WAIT/SKIP ↔ words), vista de timeline de ráster (WAITs en una tira de frame, arrastrables), y desensamblado de la propia lista de Workbench desde `GfxBase->LOFlist`. (Dos piezas ya aterrizaron por delante del modelo: el catálogo lee la lista viva para sus derivaciones de registros de solo escritura, y el restore por software tras una toma del Copper — `LOFlist` → `COP1LC`, luego `FreeMem` — está construido y demostrado en los cuadernos de ejemplo "Copper Bars — Rasterbars de la Demoscene" y "Copper Bars Nativas", **verificado en pantalla 2026-07-16**.)
- [ ] **Playfield / bitplanes**: visor de framebuffer — leer planos BPLxPT + paleta por transferencia de bloque, componer en Pharo, renderizar "lo que ve el Amiga" dentro del cuaderno; interactivos de módulo y scroll BPLCON1, prioridades de dual-playfield.
- [ ] **Sprites**: editor de píxeles en GT (16×N, 2bpp) escribiendo datos de sprite a chip RAM en vivo — dibuja en el cuaderno, míralo flotar sobre Workbench; posicionamiento arrastrable, VSTART/HSTART/attach decodificados.
- [ ] **Blitter**: constructor de tabla de verdad de minterm (elige combinaciones A/B/C → byte LF), vistas de memoria-como-bitmap antes/después alrededor de un blit vivo, disciplina `OwnBlitter`/`DisownBlitter` como lección de compartición.
- [ ] **Paula / audio**: editor de forma de onda → chip RAM, sliders de periodo/volumen — feedback inmediato que puedes *oír*.

## Más adelante

- [ ] Probar el transporte TCP en hardware real (A500 + PiStorm/Emu68 + WiFi)
- [ ] Resiliencia del monitor en `SER:`: reabrir el puerto tras un error de lectura en vez de salir (el transporte TCP ya sobrevive a la pérdida de cliente vía su bucle accept)
- [ ] Resaltado de sintaxis para ensamblador 68000 en el editor de snippets
- [ ] Modo bare-metal: generación de ADF booteable para demos hardware-directo
- [ ] Objetivo de hardware real vía [A314](https://github.com/niklasekstrom/a314)

## Libros construidos sobre Amiga ChipLab (repositorios separados)

- [ ] **El Hardware Reference del Amiga, vivo** — la materia del AHRM enseñada capítulo a capítulo, componiendo los modelos vivos de registro/máquina/chip y las figuras de ChipLab para la mejor didáctica posible.
- [ ] **Programación de videojuegos Amiga** — un juego construido paso a paso a lo largo de los capítulos.
- [ ] **Ensamblador 68000** — un curso general sobre la CPU, usando el ciclo ensamblar-y-ejecutar e inspección viva de memoria/registros.
