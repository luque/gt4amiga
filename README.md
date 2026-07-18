<div align="right"><a href="README.md">🇬🇧 English</a> · <a href="README.es.md">🇪🇸 Español</a></div>

# Amiga ChipLab

**A living, moldable model of the Amiga's custom hardware — and a platform for building interactive notebooks that teach it.**

Amiga ChipLab turns a running Amiga (real or emulated) into objects you inspect and drive in real time from [GToolkit](https://gtoolkit.com) *(GToolkit is a live Smalltalk programming environment; its Lepiter notebooks are like Jupyter, but every snippet is a live object you can inspect and reshape)*. Every custom-chip register is a live object you read and safely write, the Hardware Reference Manual's figures are **drawn from the actual machine** instead of printed, and you assemble and run 68000 assembly with the shortest feedback loop there is — all inside a Lepiter page.

> The codebase, packages and classes are named **GT4Amiga** (GT = GToolkit). *Amiga ChipLab* is the platform they make up.

## What you get

- **The chipset as live objects** — the custom registers modeled with their real access semantics (`#read`/`#write`/`#setClear`/`#strobe`), decoded bit by bit. Read them, and toggle the safe ones with a click — a write-safety policy marks which bits would cut the monitor link or hold a task, so play never bricks the machine.
  <p>
    <img src="docs/images/control-panel.png" width="720" alt="Live DMACON and INTENA control panel: every writable bit a switch, link-critical bits locked in red"><br>
    <img src="docs/images/register-diagram.png" width="497" alt="DMACON as a live bit diagram, decoded field by field">
  </p>
- **Living figures of the Hardware Reference Manual** — the DMA time-slot-per-scanline diagram (AHRM fig. 6-9) and the machine's block diagram, coloured from the *real* BPLCON0/DMACON/DDF read out of Workbench's own copper list — not static images.
  <p>
    <img src="docs/images/dma-timeslots.png" width="724" alt="The DMA time-slot-per-scanline figure (AHRM fig. 6-9), coloured from the live BPLCON0/DDFSTRT/DDFSTOP"><br>
    <img src="docs/images/block-diagram.png" width="680" alt="The A500 as a live block diagram, DMA arrows lit from the live DMACON">
  </p>
- **Drive the Amiga from a UI, in real time** — a GToolkit slider moving a Copper colour-split line, or the Workbench background colour, on the real screen — round-tripped over the monitor while you drag.
  <!-- screenshot/GIF: slider driving a live color change -->
- **Assemble and run, instantly** — from an annotated Hello World to native Copper bars at 50 fps in the vertical blank, written in a page and run as their own AmigaDOS process while the monitor keeps serving live commands.
  <!-- screenshot: copper bars on screen -->
- **A resident monitor** — peek/poke memory and chip registers, call any AmigaOS library function, and execute programs, over a small framed binary protocol (serial under FS-UAE, TCP on real hardware).

The current Lepiter pages ship as **example notebooks** that show what the platform can do; full teaching **books** (a living AHRM, game programming, 68000) are built on top of these models and live in [their own repositories](#books-built-on-amiga-chiplab).

## How it works

```
┌─ host — GToolkit (Pharo / Lepiter) ─────────────────────────────┐
│                                                                 │
│  Lepiter notebook pages                                         │
│    ├─ live hardware model — registers, machine, chips as        │
│    │    objects with gtViews that reflect AND act on the chips  │
│    └─ amiga68kSnippet — Assemble → vasmm68k_mot → hunk binary   │
│                                                                 │
│  GT4AmigaMonitorClient — protocol client (R/W/B/P/C/S/X/Q)      │
│  GT4FSUAERunner — FS-UAE lifecycle, TCP socket, run: pipeline   │
└─────────┬──────────────────────────────────┬────────────────────┘
          │ framed binary protocol           │ file exchange
          │ TCP :2345 (FS-UAE bridges SER:,  │ shared/ ⇄ GT4A:
          │ real hardware speaks TCP/IP)     │ program in, output out
┌─────────┴──────────────────────────────────┴────────────────────┐
│ Amiga — FS-UAE (Kickstart 1.3) or real A500 (PiStorm/Emu68)     │
│                                                                 │
│  gt4amiga-monitor — the only resident program                   │
│  (launched at boot by S:User-Startup)                           │
│    ├─ R / W / B / P  peek & poke memory and chip registers      │
│    ├─ C      call any AmigaOS library function, live            │
│    ├─ S      Workbench screen pointer                           │
│    ├─ Q      quit                                               │
│    └─ X      run GT4A:incoming/program as its own process       │
│                └─ Output() → GT4A:outgoing/output → Lepiter     │
│              …the monitor keeps serving commands meanwhile      │
└─────────────────────────────────────────────────────────────────┘
```

The Amiga side runs a single resident program: **gt4amiga-monitor**, launched at boot by `S:User-Startup`. It answers a small framed binary protocol — memory peek/poke, generic AmigaOS library calls, and program execution — over the serial port (which FS-UAE bridges to a TCP socket) or over a real TCP/IP stack on real hardware. The Pharo side reads and writes chip state through it to keep the live models in sync; to run a snippet, it drops the assembled executable into the shared directory and sends an execute command, and the program runs as its own AmigaDOS process with its output captured back into the notebook — all while the monitor keeps serving live commands. See [PROTOCOL.md](docs/PROTOCOL.md) for the wire format.

## Get started

Install the [prerequisites](docs/SETUP.md#prerequisites) (GToolkit, `vasmm68k_mot`, FS-UAE, a Kickstart ROM and a Workbench HDF), then follow [SETUP.md](docs/SETUP.md) for ROM/disk placement, the FS-UAE config note, and the one-time Amiga-side monitor autostart.

Load the platform — open a Pharo Playground inside GToolkit and evaluate:

```smalltalk
Metacello new
    repository: 'github://luque/gt4amiga/src';
    baseline: 'GT4Amiga';
    load.
```

Then attach the Lepiter knowledge base with the example notebooks:

```smalltalk
BaselineOfGT4Amiga loadLepiter.
```

Assemble and run 68000 assembly without even opening a page:

```smalltalk
| result |
result := GT4AmigaAssembler new assemble: '
        SECTION code,CODE
start:
        move.l  4.w,a6
        moveq   #0,d0
        rts
'.
GT4FSUAERunner default run: result.
```

## Example notebooks

Shipped as Lepiter pages, these demonstrate the platform's building blocks. (Written in Spanish.)

| Page | What it shows |
|------|---------------|
| **El Ensamblador — Primeros Pasos** | How the assembler works: three progressive examples from a minimal `rts`-only program to arithmetic and data-section access |
| **Hola Amiga — Primer Programa 68000** | AmigaOS library calling convention, `dos.library`, and a fully annotated Hello World in 68000 assembly |
| **Tomar y Liberar el Hardware — Forbid, Disable y DMA** | Taking exclusive control of Amiga hardware and releasing it cleanly so the OS survives |
| **El Bridge Server — Controlar el Amiga en Vivo** | Live peek/poke and generic library calls: reading `ExecBase`, changing the Workbench background via `SetRGB4`, and a GToolkit slider driving the color in real time |
| **El Copper — Un Split de Color en Vivo** | Building a minimal Copper list word-by-word in live chip RAM, installing it safely, and moving the color-split line in real time from a slider |
| **Lectura en Bloque — La Pantalla de Workbench dentro del Libro** | The block-transfer opcodes at work: navigating `Screen`→`BitMap`, reading the palette via `GetRGB4`, and composing the live Workbench screen as an image inside the notebook |
| **El Chipset del Amiga — Registros como Objetos Vivos** | The chip register catalog as a live model: access semantics, decoded fields, and each register's chain of knowability |
| **El Panel de Control — DMACON e INTENA con Interruptores** | The machine's control panel in Bloc: every writable bit a clickable switch, with the link-critical bits locked |
| **La Máquina — Un Diagrama de Bloques Vivo** | The whole A500 as one model: clickable block diagram with DMA arrows lit from the live DMACON, memory map with hexdumps, live memory gauges |
| **Los Time Slots de DMA — La Línea de Barrido en Vivo** | The AHRM's centerpiece figure alive: 227 color clocks per scan line, who owns each slot, and the bitplane fetch window drawn from the real BPLCON0/DDFSTRT/DDFSTOP |
| **Copper Bars — Rasterbars de la Demoscene** | The Amiga's signature demoscene effect built in Pharo, block-written to chip RAM, animated over the bridge, and the Workbench restored by software via `GfxBase->LOFlist` |
| **Copper Bars Nativas — 50 FPS en el Blanking Vertical** | The same effect the demoscene way: a native 68k program animating the bars at 50 fps in the vertical blank |

## Books built on Amiga ChipLab

Full teaching books compose ChipLab's live models and figures for the clearest possible didactics. They evolve on their own schedule, in their own repositories:

- **The living Amiga Hardware Reference** — the AHRM's subject matter, chapter by chapter, as live figures and interactive examples. *(coming soon)*
- **Amiga game programming** — a hands-on game built up over chapters. *(planned)*
- **68000 assembly** — a general course on the CPU with the assemble-and-run loop and live inspection. *(planned)*

## Project structure

```
gt4amiga/
├── src/
│   ├── BaselineOfGT4Amiga/       Metacello baseline
│   ├── GT4Amiga-Core/            Assembler wrapper, result, configuration
│   ├── GT4Amiga-FSUAE/           FS-UAE process manager
│   ├── GT4Amiga-Bridge/          Monitor client + framed wire protocol
│   ├── GT4Amiga-Hardware/        Live hardware model (registers, machine, chips)
│   ├── GT4Amiga-Hardware-UI/     Bloc views (control panel, diagrams, live figures)
│   ├── GT4Amiga-Lepiter/         Custom Lepiter snippet type and element
│   └── GT4Amiga-MCP/             Lepiter/eval server for tooling
├── lepiter/                      Lepiter knowledge base (example notebooks)
├── docs/                         Setup, wire protocol, roadmap
├── rom/                          Kickstart ROM files (git-ignored)
├── hdf/                          Workbench HDF images (git-ignored)
├── shared/                       Host↔Amiga file exchange directory
│   ├── incoming/                 Monitor binary + programs sent to the Amiga
│   └── outgoing/                 Program output captured on the Amiga
└── amiga/s/                      gt4amiga-monitor.s (the resident monitor) and AmigaDOS boot scripts
```

## Documentation

- **[Setup](docs/SETUP.md)** — prerequisites, ROM/disk, FS-UAE config, vasm, monitor autostart
- **[Wire protocol](docs/PROTOCOL.md)** — the framed binary protocol, for writing another client
- **[Roadmap](docs/ROADMAP.md)** — what's done and what's next, on the platform

## License

MIT — see [LICENSE](LICENSE).
