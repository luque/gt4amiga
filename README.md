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
| Kickstart ROM | A legal ROM dump (1.3 recommended). Cloanto/Amiga Forever encrypted ROMs (`.rom` + `rom.key`) are supported |
| Workbench HDF | An AmigaOS hard-drive image with `c/Execute`, `c/Wait`, and `c/Delete` |

## Project structure

```
gt4amiga/
├── src/
│   ├── BaselineOfGT4Amiga/       Metacello baseline
│   ├── GT4Amiga-Core/            Assembler wrapper, result, configuration
│   ├── GT4Amiga-FSUAE/           FS-UAE process manager + serial capture
│   └── GT4Amiga-Lepiter/         Custom Lepiter snippet type and element
├── lepiter/                      Lepiter knowledge base (book pages)
├── rom/                          Kickstart ROM files (git-ignored)
├── hdf/                          Workbench HDF images (git-ignored)
├── shared/                       Host↔Amiga file exchange directory
│   ├── incoming/                 Programs sent to the Amiga
│   └── outgoing/                 Output captured from the Amiga
└── amiga/s/                      AmigaDOS scripts (watcher, user-startup, startup-sequence) and gt4amiga-monitor.s (bridge server, 68k assembly)
```

## Setup

### 1. ROM and disk images

Place your files in the project directories (both are git-ignored):

```
rom/
├── kick13.rom        ← Kickstart ROM (any name, .rom extension)
└── rom.key           ← Required only for Cloanto/Amiga Forever encrypted ROMs
hdf/
└── workbench.hdf     ← Workbench hard-drive image (any name, .hdf extension)
```

`GT4AmigaConfiguration` auto-detects the first `.rom` file in `rom/` and the first `.hdf` file in `hdf/`. No manual path configuration needed.

### 2. FS-UAE config — important note

GT4Amiga writes the complete FS-UAE configuration to `~/.config/fs-uae/fs-uae.conf` every time you press **Run on FS-UAE**. This is the only path that works reliably.

**Why not a session config file?** FS-UAE has two initialisation phases:

1. **Early init** — reads `~/.config/fs-uae/fs-uae.conf` and processes all hardware options: `kickstarts_dir`, `hard_drive_*`, memory, model.
2. **Late init** — reads the file passed via `--config=`. By this point hardware setup is already done; most options (hard drives, kickstarts dir) are silently ignored.

Passing our config with `--config=` therefore causes hard drives and the Kickstart directory to be ignored, and FS-UAE falls back to the built-in AROS ROM with no disks. Writing directly to `~/.config/fs-uae/fs-uae.conf` ensures every setting takes effect.

> **Side effect**: GT4Amiga replaces this file on every run. If you use FS-UAE for other projects, back up your existing `~/.config/fs-uae/fs-uae.conf` first, or use a dedicated Linux user for GT4Amiga work.

> **Cloanto/Amiga Forever ROMs**: These are encrypted (`AMIROMTYPE1` header). Place `rom.key` (from your Amiga Forever installation) in `rom/` alongside the `.rom` file. FS-UAE decrypts them automatically when it scans `kickstarts_dir`.

### 3. vasm

`GT4AmigaConfiguration` searches for `vasmm68k_mot` in these locations, in order:

1. `/home/<you>/local/vasm/vasmm68k_mot`
2. `/usr/local/bin/vasmm68k_mot`
3. `/usr/bin/vasmm68k_mot`
4. Bare name `vasmm68k_mot` (PATH lookup)

Build from [source](http://sun.hasenbraten.de/vasm/) and place the binary in any of the above locations.

### 4. Amiga-side watcher

`amiga/s/` is the canonical, git-tracked source for the AmigaDOS scripts. `shared/s/` is the directory FS-UAE actually mounts as `GT4A:` (DH1) at runtime — it is **not** the same folder and is not tracked in git, so on a fresh checkout it doesn't exist yet. Copy the scripts there first:

```sh
mkdir -p shared/s
cp amiga/s/* shared/s/
```

`gt4amiga-watcher` re-invokes itself from `GT4A:` on every iteration (see the script's own comments for why), so after this one copy you never need to touch the HDF again to change the watcher's logic — just edit `amiga/s/gt4amiga-watcher`, re-run the `cp` above, and the next iteration on the Amiga side picks it up live.

`S:User-Startup`, however, lives *inside* the Workbench HDF image, which the host has no direct way to write into. It only needs to be set once per HDF (it's baked into the `.hdf` file itself and persists across restarts). To set it up:

1. Boot FS-UAE with the HDF (`Launch FS-UAE` from the page, or run it directly) so `GT4A:` is mounted alongside `DH0:`.
2. Open an Amiga Shell and run:
   ```
   Copy GT4A:s/user-startup S:User-Startup
   ```
   (`amiga/s/user-startup` just contains `Run >NIL: Execute GT4A:s/gt4amiga-watcher` — feel free to inspect it before copying.)
3. Reboot the Amiga (`Ctrl-Amiga-Amiga` or relaunch FS-UAE). From now on the watcher starts automatically and polls `GT4A:incoming/` for new programs, redirecting their output to the serial port.

`GT4A:` is the label FS-UAE gives to the `shared/` directory (mounted as DH1).

> **Some Workbench images never call `S:User-Startup` at all.** Amiga Forever's Workbench 1.3.5 `Startup-Sequence`, for example, ends with `LoadWB` / `EndCLI` and has no `IF EXISTS S:User-Startup` / `EXECUTE S:User-Startup` / `ENDIF` hook — so step 2 above silently has no effect: the file is copied but never executed, and the watcher doesn't start after reboot. Check with `Type S:Startup-Sequence`; if that hook is missing, install the corrected version (which adds it right before `EndCLI`) instead:
> ```
> Copy GT4A:s/startup-sequence S:Startup-Sequence
> ```
> (`amiga/s/startup-sequence` is the stock Amiga Forever WB 1.3.5 script with just that hook added — diff it against your HDF's own `Startup-Sequence` before copying if your image differs.)

### 5. Bridge server (live memory / library-call access)

Besides the one-shot assemble → deploy → run pipeline, `GT4Amiga-Bridge` provides `GT4AmigaMonitorClient`: a Pharo-side client for `amiga/s/gt4amiga-monitor.s`, a resident AmigaDOS program that answers a small binary protocol over `SER:` — memory peek/poke and generic AmigaOS library calls — without assembling and launching a new program each time. It's deliberately generic (four primitives: read/write memory, a generic library-function call, and the Workbench screen pointer) rather than one convenience method per example; worked examples (e.g. driving a live Workbench interaction from a GToolkit slider) belong as explained Lepiter snippets composing these primitives, not as methods baked into the client.

```smalltalk
GT4AmigaMonitorClient default deploy.
"then, in the Amiga Shell: Run >NIL: GT4A:incoming/monitor"

GT4AmigaMonitorClient default workbenchScreenPointer.
GT4AmigaMonitorClient default readMemoryAt: 16r00DFF180 size: 2. "COLOR00"
```

The monitor and the one-shot watcher pipeline share the single emulated serial port, so only one can be in use at a time. See the class comment on `GT4AmigaMonitorClient` for the full protocol and the design dead-ends already ruled out (notably: `LockPubScreen()` is Kickstart 2.0+ only and does not exist on the Kickstart 1.3 target this project uses).

> **Resolved (2026-07-09)**: an earlier version of this section documented a "systemic crash" when `callLibrary:lvo:...` targeted `intuition.library`/`graphics.library`. Root-caused and fixed — it was three 68k register-hygiene bugs in `gt4amiga-monitor.s` (mutating `a6` before the `jsr` instead of using indexed addressing; `move.b` into an uncleared `d4` producing gigantic byte counts; loading `a0` before a `dos.library/Read()` call that clobbers it). All four primitives are now verified end-to-end, including `MoveScreen` and `SetRGB4` calls and a write-then-readback memory test. The full post-mortem — including the Python-over-TCP probe technique that isolated the bugs in minutes after hours of in-image debugging — is in the class comment on `GT4AmigaMonitorClient`.

## Loading in GToolkit

Open a Pharo Playground inside GToolkit and evaluate:

```smalltalk
Metacello new
    repository: 'github://luque/gt4amiga/src';
    baseline: 'GT4Amiga';
    load.
```

This loads `GT4Amiga-Core`, `GT4Amiga-FSUAE`, and `GT4Amiga-Lepiter`, and registers the custom `amiga68kSnippet` type with Lepiter automatically.

Then attach the Lepiter knowledge base:

```smalltalk
BaselineOfGT4Amiga loadLepiter.
```

The book pages will appear in the Lepiter browser.

## Book contents

| Page | Description |
|------|-------------|
| **El Ensamblador — Primeros Pasos** | How the assembler works: three progressive examples from a minimal `rts`-only program to arithmetic and data-section access |
| **Hola Amiga — Primer Programa 68000** | AmigaOS library calling convention, `dos.library`, and a fully annotated Hello World in 68000 assembly |
| **Tomar y Liberar el Hardware — Forbid, Disable y DMA** | Taking exclusive control of Amiga hardware (`Forbid`/`Disable`, DMA takeover) and releasing it cleanly so the OS survives, adapted from *Amiga Assembly Game Programming* chapter 4 |
| **El Bridge Server — Controlar el Amiga en Vivo** | Live peek/poke and generic library calls over the serial bridge: reading `ExecBase`, changing the Workbench background color via `SetRGB4`, and a GToolkit slider driving the color in real time |

## Quick start (Playground)

Assemble without opening a Lepiter page:

```smalltalk
GT4AmigaAssembler new assemble: '
        SECTION code,CODE
start:
        move.l  4.w,a6
        moveq   #0,d0
        rts
'
```

Assemble and run on FS-UAE:

```smalltalk
| result |
result := GT4AmigaAssembler new assemble: '...'.
GT4FSUAERunner default run: result.
```

## Roadmap

- [x] 68000 assembler integration (`vasmm68k_mot`)
- [x] FS-UAE runner with shared-directory file exchange and serial capture
- [x] Custom `amiga68kSnippet` type for Lepiter pages
- [x] Auto-detection of vasm, Kickstart ROM and Workbench HDF paths
- [x] First book pages: assembler primer + AmigaOS Hello World
- [x] Second book page: taking and releasing hardware control (`Forbid`/`Disable`, DMA)
- [x] Bridge server (`GT4AmigaMonitorClient`): live memory/library-call access over SER: — all four primitives verified end-to-end, including `intuition.library`/`graphics.library` calls (`MoveScreen`, `SetRGB4`)
- [x] Bridge server book page ("El Bridge Server — Controlar el Amiga en Vivo"): live reads, `SetRGB4` color change, GToolkit slider driving the background color in real time
- [ ] More bridge server examples (e.g. a slider driving a live Copper split line)
- [ ] Syntax highlighting for 68000 assembly in the snippet editor
- [ ] Bare-metal mode: bootable ADF generation for hardware-direct demos
- [ ] Real hardware target via [A314](https://github.com/niklasekstrom/a314)
- [ ] Copper list visualiser and custom-chip register reference

## License

MIT — see [LICENSE](LICENSE).
