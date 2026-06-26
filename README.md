# GT4Amiga

An interactive book for learning **Commodore Amiga low-level programming** — 68000 assembly and custom hardware — built on [GToolkit](https://gtoolkit.com) and its Lepiter knowledge-management system.

GT4Amiga lets you write Motorola 68000 assembly directly inside a Lepiter page, assemble it with `vasmm68k_mot`, and run it on a real Amiga or an [FS-UAE](https://fs-uae.net) emulator — with the shortest possible feedback loop.

## How it works

```
Lepiter page (GToolkit)
  └─ amiga68kSnippet
       ├─ Assemble  →  vasmm68k_mot  →  AmigaOS hunk executable
       └─ Run       →  shared dir  →  FS-UAE / real Amiga (via A314)
                                           │
                                    serial port (TCP)
                                           │
                                    output back in Lepiter
```

The Amiga side runs a small AmigaDOS watcher script that detects new programs dropped into a shared directory, executes them, and redirects their output to the serial port. GToolkit reads from the TCP socket that FS-UAE maps the serial port to and displays the result in the notebook.

## Prerequisites

| Tool | Notes |
|------|-------|
| [GToolkit](https://gtoolkit.com) | The Pharo-based live environment that hosts the book |
| `vasmm68k_mot` | Motorola-syntax 68k assembler. Build from [source](http://sun.hasenbraten.de/vasm/) or install via your package manager |
| [FS-UAE](https://fs-uae.net) | Amiga emulator (for the emulator target) |
| Kickstart ROM | A legal dump from your own Amiga (1.3, 2.0 or 3.1 recommended) |
| Workbench HDF | A minimal AmigaOS hard-drive image with `c/Execute`, `c/Wait`, and `c/Delete` |

## Loading in GToolkit

Open a Pharo Playground inside GToolkit and evaluate:

```smalltalk
Metacello new
    repository: 'github://luque/gt4amiga/src';
    baseline: 'GT4Amiga';
    load.
```

This loads the three packages (`GT4Amiga-Core`, `GT4Amiga-FSUAE`, `GT4Amiga-Lepiter`) and registers the custom `amiga68kSnippet` type with Lepiter automatically.

## Initial setup

Configure the paths to your local tools and ROM images once, then forget about it:

```smalltalk
GT4AmigaConfiguration default
    vasmPath: '/usr/local/bin/vasmm68k_mot';
    fsuaePath: '/usr/bin/fs-uae';
    kickstartPath: '/path/to/kick13.rom' asFileReference;
    workbenchHdfPath: '/path/to/workbench.hdf' asFileReference;
    sharedDirectory: '/path/to/gt4amiga/shared' asFileReference;
    serialPort: 2345;
    yourself.
```

### Amiga-side watcher

Copy the contents of `amiga/s/` to your Workbench disk image and add the following line to `s/user-startup`:

```
Run >NIL: GT4A:s/gt4amiga-watcher
```

This starts the poll loop that watches for programs sent from the host and redirects their output to the serial port.

## Quick start

Evaluate this in a GToolkit Playground to assemble and inspect a result without opening a Lepiter page:

```smalltalk
GT4AmigaAssembler new assemble: '
        SECTION code,CODE
start:
        move.l  4.w,a6
        moveq   #0,d0
        rts
'
```

To assemble and run on FS-UAE:

```smalltalk
| result |
result := GT4AmigaAssembler new assemble: '...'.
GT4FSUAERunner default run: result.
```

## Opening the book

After loading the project, attach the Lepiter database to GToolkit:

```smalltalk
LeDatabasesRegistry uniqueInstance
    loadAndMonitorDatabase:
        LeLocalStoreBasedDatabase new
            localStoreRootDirectory:
                '/path/to/gt4amiga/lepiter' asFileReference.
```

The book pages will appear in the Lepiter browser. The first page, **"Hola Amiga — Primer Programa 68000"**, walks through the AmigaOS library calling convention and a fully annotated Hello World in 68000 assembly.

## Project structure

```
gt4amiga/
├── src/
│   ├── BaselineOfGT4Amiga/       Metacello baseline
│   ├── GT4Amiga-Core/            Assembler wrapper, result, configuration
│   ├── GT4Amiga-FSUAE/           FS-UAE process manager + serial capture
│   └── GT4Amiga-Lepiter/         Custom Lepiter snippet type and element
├── lepiter/                      Lepiter knowledge base (book pages)
├── amiga/s/                      AmigaDOS scripts (watcher, user-startup)
└── configs/fsuae/                FS-UAE configuration template
```

## Roadmap

- [x] 68000 assembler integration (`vasmm68k_mot`)
- [x] FS-UAE runner with shared-directory file exchange and serial capture
- [x] Custom `amiga68kSnippet` type for Lepiter pages
- [x] First book page: AmigaOS library calling convention + Hello World
- [ ] Syntax highlighting for 68000 assembly in the snippet editor
- [ ] Bare-metal mode: bootable ADF generation for hardware-direct demos
- [ ] Real hardware target via [A314](https://github.com/niklasekstrom/a314)
- [ ] Copper list visualiser and custom-chip register reference

## License

MIT — see [LICENSE](LICENSE).
