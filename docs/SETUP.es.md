<div align="right"><a href="SETUP.md">🇬🇧 English</a> · <a href="SETUP.es.md">🇪🇸 Español</a></div>

# Instalación — Amiga ChipLab

[← Volver al README](../README.es.md)

Todo lo necesario para poner la plataforma en marcha contra FS-UAE (o hardware real). El código, los paquetes y las clases se llaman **GT4Amiga**; "Amiga ChipLab" es la plataforma.

## Prerequisitos

| Herramienta | Notas |
|-------------|-------|
| [GToolkit](https://gtoolkit.com) | El entorno vivo basado en Pharo que hospeda la plataforma |
| `vasmm68k_mot` | Ensamblador 68k de sintaxis Motorola. Compílalo desde [las fuentes](http://sun.hasenbraten.de/vasm/) o instálalo con tu gestor de paquetes |
| [FS-UAE](https://fs-uae.net) | Emulador de Amiga (para el objetivo emulador) |
| ROM de Kickstart | Un volcado legal de ROM (1.3 recomendado). Se admiten las ROM cifradas de Cloanto/Amiga Forever (`.rom` + `rom.key`) |
| HDF de Workbench | Una imagen de disco duro de AmigaOS con `c/Run` (cualquier Workbench estándar lo tiene) |

## 1. Imágenes de ROM y disco

Coloca tus ficheros en los directorios del proyecto (ambos ignorados por git):

```
rom/
├── kick13.rom        ← ROM de Kickstart (cualquier nombre, extensión .rom)
└── rom.key           ← Solo para ROM cifradas de Cloanto/Amiga Forever
hdf/
└── workbench.hdf     ← Imagen de disco duro de Workbench (cualquier nombre, extensión .hdf)
```

`GT4AmigaConfiguration` autodetecta el primer fichero `.rom` en `rom/` y el primer `.hdf` en `hdf/`. No hace falta configurar rutas a mano.

## 2. Config de FS-UAE — nota importante

GT4Amiga escribe la configuración completa de FS-UAE en `~/.config/fs-uae/fs-uae.conf` cada vez que pulsas **Run on FS-UAE**. Es el único camino que funciona de forma fiable.

**¿Por qué no un fichero de configuración de sesión?** FS-UAE tiene dos fases de inicialización:

1. **Init temprano** — lee `~/.config/fs-uae/fs-uae.conf` y procesa todas las opciones de hardware: `kickstarts_dir`, `hard_drive_*`, memoria, modelo.
2. **Init tardío** — lee el fichero pasado con `--config=`. A esas alturas el hardware ya está configurado; la mayoría de opciones (discos duros, directorio de kickstarts) se ignoran en silencio.

Pasar nuestra config con `--config=` provoca por tanto que se ignoren los discos duros y el directorio de Kickstart, y FS-UAE cae de nuevo a la ROM AROS integrada sin discos. Escribir directamente en `~/.config/fs-uae/fs-uae.conf` asegura que cada ajuste surta efecto.

> **Efecto secundario**: GT4Amiga reemplaza este fichero en cada ejecución. Si usas FS-UAE para otros proyectos, haz copia de tu `~/.config/fs-uae/fs-uae.conf` primero, o usa un usuario de Linux dedicado para trabajar con GT4Amiga.

> **ROM de Cloanto/Amiga Forever**: Están cifradas (cabecera `AMIROMTYPE1`). Coloca `rom.key` (de tu instalación de Amiga Forever) en `rom/` junto al fichero `.rom`. FS-UAE las descifra automáticamente al escanear `kickstarts_dir`.

## 3. vasm

`GT4AmigaConfiguration` busca `vasmm68k_mot` en estas ubicaciones, en orden:

1. `/home/<tú>/local/vasm/vasmm68k_mot`
2. `/usr/local/bin/vasmm68k_mot`
3. `/usr/bin/vasmm68k_mot`
4. Nombre a secas `vasmm68k_mot` (búsqueda en PATH)

Compílalo desde [las fuentes](http://sun.hasenbraten.de/vasm/) y coloca el binario en cualquiera de las ubicaciones anteriores.

## 4. Autoarranque del monitor en el lado Amiga

El único programa del lado Amiga es el monitor residente. Vive en `GT4A:incoming/monitor` — es decir, en el host `shared/incoming/monitor`, donde `GT4AmigaMonitorClient default deploy` lo ensambla — y `S:User-Startup` lo lanza en cada arranque (`Run >NIL: GT4A:incoming/monitor`, protegido por `IF EXISTS`). Actualizar el monitor nunca toca el HDF: despliega el nuevo binario y reinicia el Amiga.

`amiga/s/` es la fuente canónica, versionada en git, de los scripts de arranque. `shared/s/` es el directorio que FS-UAE monta como `GT4A:` (DH1) en tiempo de ejecución — **no** es la misma carpeta y no está versionada en git, así que en un checkout limpio aún no existe. Copia los scripts allí primero:

```sh
mkdir -p shared/s
cp amiga/s/* shared/s/
```

`S:User-Startup` vive *dentro* de la imagen HDF de Workbench, en la que el host no tiene forma directa de escribir. Solo hay que configurarlo una vez por HDF (queda grabado en el propio fichero `.hdf` y persiste entre reinicios). Para configurarlo:

1. Arranca FS-UAE con el HDF (`Launch FS-UAE` desde la página, o ejecútalo directamente) para que `GT4A:` quede montado junto a `DH0:`.
2. Abre una Shell del Amiga y ejecuta:
   ```
   Copy GT4A:s/user-startup S:User-Startup
   ```
   (`amiga/s/user-startup` solo contiene el `Run >NIL: GT4A:incoming/monitor` protegido — inspecciónalo antes de copiar si quieres.)
3. Reinicia el Amiga (`Ctrl-Amiga-Amiga` o relanza FS-UAE). A partir de ahora el monitor arranca solo al inicio.

`GT4A:` es la etiqueta que FS-UAE da al directorio `shared/` (montado como DH1).

> **Configuración serie de una sola vez (necesaria para el bridge server)**: AmigaOS trae el control de flujo software XON/XOFF activado en `serial.device`. Un protocolo binario tarde o temprano contendrá un byte `$13` (XOFF) — un checksum, un valor de datos — que la capa serie consume en silencio *y además* pausa la transmisión del Amiga, haciendo que el monitor parezca morir en valores reproducibles del protocolo. Abre **Preferences → Serial** en el Workbench, pon **Handshaking: None**, y Save (persiste en `Devs:system-configuration` del HDF). El transporte TCP usado en hardware real es inmune — esto solo afecta al modo `SER:`/FS-UAE.

> **Algunas imágenes de Workbench nunca llaman a `S:User-Startup`.** El `Startup-Sequence` del Workbench 1.3.5 de Amiga Forever, por ejemplo, termina con `LoadWB` / `EndCLI` y no tiene el gancho `IF EXISTS S:User-Startup` / `EXECUTE S:User-Startup` / `ENDIF` — así que el paso 2 de arriba no tiene efecto en silencio: el fichero se copia pero nunca se ejecuta. Comprueba con `Type S:Startup-Sequence`; si falta ese gancho, instala la versión corregida (que lo añade justo antes de `EndCLI`):
> ```
> Copy GT4A:s/startup-sequence S:Startup-Sequence
> ```
> (`amiga/s/startup-sequence` es el script estándar del WB 1.3.5 de Amiga Forever con solo ese gancho añadido — compáralo con el `Startup-Sequence` de tu propio HDF antes de copiar si tu imagen difiere.)

## 5. El monitor (ejecución de programas + acceso vivo a memoria / llamadas a librerías)

`GT4Amiga-Bridge` provee `GT4AmigaMonitorClient`: el cliente del lado Pharo para `amiga/s/gt4amiga-monitor.s`, el programa residente que responde a un pequeño protocolo binario enmarcado — peek/poke de memoria, llamadas genéricas a librerías de AmigaOS, y ejecución de programas. El pipeline de un tiro ensamblar → ejecutar (`GT4FSUAERunner run:`) también pasa por él: el ejecutable se deja en `shared/incoming/program` y se lanza con el opcode de ejecución como un proceso de AmigaDOS separado, con su `Output()` capturado a `shared/outgoing/output` — el monitor sigue sirviendo comandos en vivo *mientras el programa corre*. El cliente es deliberadamente genérico (leer/escribir memoria, una llamada genérica a función de librería, el puntero a la pantalla de Workbench, ejecutar programa) en vez de un método de conveniencia por ejemplo; los ejemplos trabajados (p. ej. manejar una interacción viva con Workbench desde un slider de GToolkit) van como snippets Lepiter explicados que componen estas primitivas, no como métodos incrustados en el cliente.

El monitor autoselecciona entre **dos transportes** al arrancar:

- **TCP (`bsdsocket.library`)** — para hardware real con una pila TCP/IP en marcha (p. ej. un A500 acelerado con PiStorm/Emu68, WiFi vía `wifipi.device` + Roadshow). El monitor se convierte en un servidor TCP en el puerto 2345; apunta GToolkit a él con `GT4AmigaConfiguration default monitorHost: '<ip-del-amiga>'`. Los clientes pueden desconectar y reconectar libremente — el monitor hace `accept()` de la siguiente conexión.
- **`SER:` (dos.library)** — alternativa cuando no hay pila TCP (p. ej. Workbench 1.3 bajo FS-UAE, donde FS-UAE puentea el puerto serie emulado a un socket TCP del host). Es el montaje clásico del emulador y no necesita configuración (`monitorHost` es `127.0.0.1` por defecto).

El protocolo de cable es byte a byte idéntico en ambos transportes, así que el cliente Pharo y cada ejemplo del libro funcionan sin cambios contra el emulador o la máquina real. Para hardware real, copia el binario `monitor` ensamblado una vez por el medio que ofrezca tu red (FTP/SMB), luego `Run >NIL: monitor` desde una Shell.

```smalltalk
GT4AmigaMonitorClient default deploy.
"lanzado en el siguiente arranque por S:User-Startup (paso 4 de arriba)"

GT4AmigaMonitorClient default workbenchScreenPointer.
GT4AmigaMonitorClient default readMemoryAt: 16r00DFF180 size: 2. "COLOR00"

"ejecuta un programa mientras el monitor sigue sirviendo comandos (opcode X):
 pon el ejecutable en shared/incoming/program primero - o usa directamente
 GT4FSUAERunner default run: anAssemblyResult, que hace todo esto"
| c mb |
c := GT4AmigaMonitorClient default.
mb := c executeProgram.            "dirección del mailbox, o nil"
c waitForProgramAt: mb timeout: 30 seconds.   "el código de retorno del programa"
c capturedOutput.                  "su Output(), desde shared/outgoing/output"
```

Consulta el comentario de clase de `GT4AmigaMonitorClient` para el protocolo completo y los callejones sin salida de diseño ya descartados (en particular: `LockPubScreen()` es solo Kickstart 2.0+ y no existe en el Kickstart 1.3 que usa este proyecto). El protocolo de cable en sí está documentado en [PROTOCOL.es.md](PROTOCOL.es.md).

> **Resuelto (2026-07-09)**: una versión anterior de esta sección documentaba un "crash sistémico" cuando `callLibrary:lvo:...` apuntaba a `intuition.library`/`graphics.library`. Diagnosticado y corregido — eran tres bugs de higiene de registros 68k en `gt4amiga-monitor.s` (mutar `a6` antes del `jsr` en vez de usar direccionamiento indexado; `move.b` a un `d4` sin limpiar produciendo cuentas de bytes gigantescas; cargar `a0` antes de una llamada a `dos.library/Read()` que lo pisa). Las cuatro primitivas están ahora verificadas de punta a punta, incluyendo llamadas `MoveScreen` y `SetRGB4` y un test de escritura-y-relectura de memoria. El post-mortem completo — incluida la técnica de sonda Python-sobre-TCP que aisló los bugs en minutos tras horas de depuración en la imagen — está en el comentario de clase de `GT4AmigaMonitorClient`.
