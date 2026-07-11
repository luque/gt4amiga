# GT4Amiga

An interactive book for learning **Commodore Amiga low-level programming** — 68000 assembly and custom hardware — built on [GToolkit](https://gtoolkit.com) and its Lepiter knowledge-management system.

GT4Amiga lets you write Motorola 68000 assembly directly inside a Lepiter page, assemble it with `vasmm68k_mot`, and run it on a real Amiga or an [FS-UAE](https://fs-uae.net) emulator — with the shortest possible feedback loop.

## How it works

```
┌─ host — GToolkit (Pharo / Lepiter) ─────────────────────────────┐
│                                                                 │
│  Lepiter book pages — amiga68kSnippet                           │
│    ├─ Assemble → GT4AmigaAssembler → vasmm68k_mot → hunk binary │
│    └─ Run ↴                                                     │
│                                                                 │
│  GT4AmigaMonitorClient — protocol client (R/W/C/S/X/Q)          │
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
│    ├─ R / W  peek & poke memory and chip registers, live        │
│    ├─ C      call any AmigaOS library function, live            │
│    ├─ S      Workbench screen pointer                           │
│    ├─ Q      quit                                               │
│    └─ X      run GT4A:incoming/program as its own process       │
│                └─ Output() → GT4A:outgoing/output → Lepiter     │
│              …the monitor keeps serving commands meanwhile      │
└─────────────────────────────────────────────────────────────────┘
```

The Amiga side runs a single resident program: **gt4amiga-monitor**, launched at boot by `S:User-Startup`. It answers a small framed binary protocol — memory peek/poke, generic AmigaOS library calls, and program execution — over the serial port (which FS-UAE bridges to a TCP socket) or over a real TCP/IP stack on real hardware. To run a snippet, GToolkit drops the assembled executable into the shared directory and sends the monitor an execute command; the program runs as its own AmigaDOS process with its output captured to a file in the shared directory, which GToolkit reads back and displays in the notebook — all while the monitor keeps serving live commands.

## Prerequisites

| Tool | Notes |
|------|-------|
| [GToolkit](https://gtoolkit.com) | The Pharo-based live environment that hosts the book |
| `vasmm68k_mot` | Motorola-syntax 68k assembler. Build from [source](http://sun.hasenbraten.de/vasm/) or install via your package manager |
| [FS-UAE](https://fs-uae.net) | Amiga emulator (for the emulator target) |
| Kickstart ROM | A legal ROM dump (1.3 recommended). Cloanto/Amiga Forever encrypted ROMs (`.rom` + `rom.key`) are supported |
| Workbench HDF | An AmigaOS hard-drive image with `c/Run` (any stock Workbench has it) |

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
│   ├── incoming/                 Monitor binary + programs sent to the Amiga
│   └── outgoing/                 Program output captured on the Amiga
└── amiga/s/                      gt4amiga-monitor.s (the resident monitor, 68k assembly) and AmigaDOS boot scripts (user-startup, startup-sequence)
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

### 4. Amiga-side monitor autostart

The only Amiga-side program is the resident monitor. It lives at `GT4A:incoming/monitor` — that is, host-side `shared/incoming/monitor`, where `GT4AmigaMonitorClient default deploy` assembles it to — and `S:User-Startup` launches it at every boot (`Run >NIL: GT4A:incoming/monitor`, guarded by `IF EXISTS`). Updating the monitor never touches the HDF: deploy the new binary and reboot the Amiga.

`amiga/s/` is the canonical, git-tracked source for the boot scripts. `shared/s/` is the directory FS-UAE actually mounts as `GT4A:` (DH1) at runtime — it is **not** the same folder and is not tracked in git, so on a fresh checkout it doesn't exist yet. Copy the scripts there first:

```sh
mkdir -p shared/s
cp amiga/s/* shared/s/
```

`S:User-Startup` lives *inside* the Workbench HDF image, which the host has no direct way to write into. It only needs to be set once per HDF (it's baked into the `.hdf` file itself and persists across restarts). To set it up:

1. Boot FS-UAE with the HDF (`Launch FS-UAE` from the page, or run it directly) so `GT4A:` is mounted alongside `DH0:`.
2. Open an Amiga Shell and run:
   ```
   Copy GT4A:s/user-startup S:User-Startup
   ```
   (`amiga/s/user-startup` just contains the guarded `Run >NIL: GT4A:incoming/monitor` — feel free to inspect it before copying.)
3. Reboot the Amiga (`Ctrl-Amiga-Amiga` or relaunch FS-UAE). From now on the monitor starts automatically at boot.

`GT4A:` is the label FS-UAE gives to the `shared/` directory (mounted as DH1).

> **One-time serial setup (required for the bridge server)**: AmigaOS ships with XON/XOFF software flow control enabled on `serial.device`. A binary protocol will sooner or later contain a `$13` (XOFF) byte — a checksum, a data value — which the serial layer silently consumes *and* pauses the Amiga's transmission, making the monitor appear to die at reproducible protocol values. Open **Preferences → Serial** on the Workbench, set **Handshaking: None**, and Save (persists in the HDF's `Devs:system-configuration`). The TCP transport used on real hardware is immune — this only affects the `SER:`/FS-UAE mode.

> **Some Workbench images never call `S:User-Startup` at all.** Amiga Forever's Workbench 1.3.5 `Startup-Sequence`, for example, ends with `LoadWB` / `EndCLI` and has no `IF EXISTS S:User-Startup` / `EXECUTE S:User-Startup` / `ENDIF` hook — so step 2 above silently has no effect: the file is copied but never executed, and the watcher doesn't start after reboot. Check with `Type S:Startup-Sequence`; if that hook is missing, install the corrected version (which adds it right before `EndCLI`) instead:
> ```
> Copy GT4A:s/startup-sequence S:Startup-Sequence
> ```
> (`amiga/s/startup-sequence` is the stock Amiga Forever WB 1.3.5 script with just that hook added — diff it against your HDF's own `Startup-Sequence` before copying if your image differs.)

### 5. The monitor (program execution + live memory / library-call access)

`GT4Amiga-Bridge` provides `GT4AmigaMonitorClient`: the Pharo-side client for `amiga/s/gt4amiga-monitor.s`, the resident program that answers a small framed binary protocol — memory peek/poke, generic AmigaOS library calls, and program execution. The one-shot assemble → run pipeline (`GT4FSUAERunner run:`) goes through it too: the executable is dropped at `shared/incoming/program` and launched with the execute opcode as a separate AmigaDOS process, with its `Output()` captured to `shared/outgoing/output` — the monitor keeps serving live commands *while the program runs*. The client is deliberately generic (read/write memory, a generic library-function call, the Workbench screen pointer, execute program) rather than one convenience method per example; worked examples (e.g. driving a live Workbench interaction from a GToolkit slider) belong as explained Lepiter snippets composing these primitives, not as methods baked into the client.

The monitor auto-selects between **two transports** at startup:

- **TCP (`bsdsocket.library`)** — for real hardware with a running TCP/IP stack (e.g. an A500 accelerated with PiStorm/Emu68, WiFi via `wifipi.device` + Roadshow). The monitor becomes a TCP server on port 2345; point GToolkit at it with `GT4AmigaConfiguration default monitorHost: '<amiga-ip>'`. Clients may disconnect and reconnect freely — the monitor `accept()`s the next connection.
- **`SER:` (dos.library)** — fallback when no TCP stack exists (e.g. Workbench 1.3 under FS-UAE, where FS-UAE bridges the emulated serial port to a host TCP socket). This is the classic emulator setup and needs no configuration (`monitorHost` defaults to `127.0.0.1`).

The wire protocol is byte-identical on both transports, so the Pharo client and every book example work unchanged against the emulator or the real machine. For real hardware, copy the assembled `monitor` binary over once by whatever means your network offers (FTP/SMB), then `Run >NIL: monitor` from a Shell.

```smalltalk
GT4AmigaMonitorClient default deploy.
"launched at the next boot by S:User-Startup (setup step 4 above)"

GT4AmigaMonitorClient default workbenchScreenPointer.
GT4AmigaMonitorClient default readMemoryAt: 16r00DFF180 size: 2. "COLOR00"

"run a program while the monitor keeps serving commands (opcode X):
 put the executable at shared/incoming/program first - or just use
 GT4FSUAERunner default run: anAssemblyResult, which does all of this"
| c mb |
c := GT4AmigaMonitorClient default.
mb := c executeProgram.            "mailbox address, or nil"
c waitForProgramAt: mb timeout: 30 seconds.   "the program's return code"
c capturedOutput.                  "its Output(), from shared/outgoing/output"
```

See the class comment on `GT4AmigaMonitorClient` for the full protocol and the design dead-ends already ruled out (notably: `LockPubScreen()` is Kickstart 2.0+ only and does not exist on the Kickstart 1.3 target this project uses).

> **Resolved (2026-07-09)**: an earlier version of this section documented a "systemic crash" when `callLibrary:lvo:...` targeted `intuition.library`/`graphics.library`. Root-caused and fixed — it was three 68k register-hygiene bugs in `gt4amiga-monitor.s` (mutating `a6` before the `jsr` instead of using indexed addressing; `move.b` into an uncleared `d4` producing gigantic byte counts; loading `a0` before a `dos.library/Read()` call that clobbers it). All four primitives are now verified end-to-end, including `MoveScreen` and `SetRGB4` calls and a write-then-readback memory test. The full post-mortem — including the Python-over-TCP probe technique that isolated the bugs in minutes after hours of in-image debugging — is in the class comment on `GT4AmigaMonitorClient`.

## Monitor wire protocol (v2, framed)

Reference for writing another client (the Pharo implementation is `GT4AmigaMonitorClient`, the Amiga implementation `amiga/s/gt4amiga-monitor.s` — both carry the full design history in their comments). The protocol is byte-identical over both transports (`SER:` under FS-UAE, TCP on real hardware). All multi-byte values are **big-endian** (68k native).

**Command frame** (host → Amiga):

```
[$A5] [opcode] [payload…] [chk]     chk = XOR of opcode and every payload byte
```

**Response frame** (Amiga → host):

```
[$5A] [status] [payload…] [chk]     chk = XOR of status and every payload byte
```

`status 0` = OK, executed; the payload follows. `status 1` = **NAK**: the checksum did not match and **nothing was executed** — always safe to resend, even a CALL or an EXEC. A NAK frame carries no payload (`[$5A][$01][$01]`).

**Commands** (opcodes are the ASCII letters):

| Op | Payload | OK-response payload |
|----|---------|---------------------|
| `R` `$52` read memory | `[size:1][pad:1][addr:4]` — size 1, 2 or 4 | the `size` bytes read |
| `W` `$57` write memory | `[size:1][pad:1][addr:4][data × size]` | empty (ack) |
| `C` `$43` call library | `[lib:1][pad:1][lvo:2 signed][a0:4][a1:4][d0:4][d1:4][d2:4][d3:4]` | `d0` after the call (4 bytes) |
| `S` `$53` screen pointer | none | `IntuitionBase->FirstScreen` (4 bytes) |
| `X` `$58` execute program | none | execution-mailbox address (4 bytes), or `0` if nothing was launched |
| `Q` `$51` quit | none | empty; the monitor then exits |

`lib` for CALL: `0` = exec, `1` = dos.library, `2` = intuition.library, `3` = graphics.library (bases opened once at monitor startup). `lvo` is the signed 16-bit library vector offset (e.g. FindTask = `-294`).

`X` loads `GT4A:incoming/program` and runs it as a separate AmigaDOS process with its `Output()` captured to `GT4A:outgoing/output`; the monitor keeps serving commands meanwhile. Completion is polled by the host through ordinary `R` reads of the mailbox: `+0` state byte (`0` never ran, `1` running, `2` done, `3` launch error), `+4` return-code long (the program's final `d0`, valid at state 2). An `X` while state is `1`, or whose `LoadSeg`/`CreateProc` fails, answers `0`.

**Retry rules** (what the Pharo client implements, and any client should):

- **NAK** → resend, always. Nothing ran on the Amiga side.
- **Silence or a corrupt response** → execution is *uncertain*: the command may have run and only its response been lost. Retry only the idempotent commands — `R`, `W`, `S` — and never `C` or `X` (a library call or a program launch could execute twice).
- A fully silent retry round usually means the connection itself is dead (e.g. the peer closed and the socket sits in CLOSE-WAIT): force a reconnect and try once more.

**Resynchronisation**: the monitor's parser *hunts* the `$A5` sync byte — after any mutilated frame it discards bytes until the next `$A5`, so it recovers by itself; a `$A5` inside a payload is harmless in normal operation because frame bodies are read by length, not scanned. A `W` whose `size` byte is not 1, 2 or 4 is discarded outright (realign, no NAK) — a corrupt size must never become a read count. On the wire the serial layer must be free of XON/XOFF flow control, or `$11`/`$13` payload bytes will be eaten in transit — see the one-time serial setup note above.

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
| **El Copper — Un Split de Color en Vivo** | Building a minimal Copper list word-by-word in live chip RAM (MOVE/WAIT encoding from the Hardware Reference Manual), installing it safely, and moving the color-split line in real time from a GToolkit slider |

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

### Done

- [x] 68000 assembler integration (`vasmm68k_mot`)
- [x] FS-UAE runner with shared-directory file exchange and serial capture
- [x] Custom `amiga68kSnippet` type for Lepiter pages
- [x] Auto-detection of vasm, Kickstart ROM and Workbench HDF paths
- [x] First book pages: assembler primer + AmigaOS Hello World
- [x] Second book page: taking and releasing hardware control (`Forbid`/`Disable`, DMA)
- [x] Bridge server (`GT4AmigaMonitorClient`): live memory/library-call access over SER: — all four primitives verified end-to-end, including `intuition.library`/`graphics.library` calls (`MoveScreen`, `SetRGB4`)
- [x] Bridge server book page ("El Bridge Server — Controlar el Amiga en Vivo"): live reads, `SetRGB4` color change, GToolkit slider driving the background color in real time
- [x] Copper book page ("El Copper — Un Split de Color en Vivo"): hand-built Copper list in live chip RAM, slider moving the split line
- [x] Framed monitor protocol (v2): sync byte `$A5` + XOR checksum + NAK/retry semantics, so serial byte loss is a detectable, retryable error instead of silent memory corruption; the monitor re-syncs itself after any corrupt frame
- [x] Monitor transport abstraction: TCP server via `bsdsocket.library` (real hardware over the network) with `SER:` fallback (FS-UAE), auto-selected at startup; stack discipline fixed so link-loss exits are clean from any call depth

### Next: one resident program (monitor absorbs the watcher)

Goal: the monitor becomes the *only* resident program on the Amiga side, replacing the polling watcher script. This removes the SER: contention between watcher and monitor, the 1-second trigger-polling latency, and the trigger/done-marker race — and the one-shot run pipeline inherits the framed protocol's checksum/retry reliability for free. It also works unchanged over the TCP transport on real hardware, where the watcher's `>SER:` redirect does not exist.

- [x] New monitor opcode `X` (execute): load `GT4A:incoming/program` with `LoadSeg()` and launch it as a **separate process** via `CreateProc()` (dos.library V34 — present on Kickstart 1.3), not an in-process `jsr`. The monitor acks immediately and returns to its command loop, so `R`/`W`/`C` keep working *while the program runs* — live inspection of a running program from GToolkit. **Verified end-to-end (2026-07-11)**: 12 `R` + 12 `S` commands serviced while a 5-second test program ran, return code and captured output both correct, immediate relaunch OK — from both a reference Python client and `GT4AmigaMonitorClient` (`executeProgram` / `waitForProgramAt:timeout:` / `capturedOutput`). (A transitional `monitor-trigger` hook in the watcher was used to bootstrap the monitor for these tests, then retired along with the watcher itself — see the next item.) Design notes:
  - A small stub runs inside the child process: it opens the output-capture file and installs it as its own `pr_COS` (a `CreateProc()`'d process has no CLI context, so `Output()` would return 0 otherwise — book examples keep using `Output()`/`Write()` unchanged), `jsr`s into the loaded seglist, then writes a completion flag + return code at a known address before exiting.
  - Completion is polled by the host (via `R` on the flag address, or a dedicated status opcode) — Kickstart 1.3 has no process-death notification.
  - Program output goes to a capture file, never raw onto the wire: free-form text interleaved with binary frames on the same channel is asking for a new gremlin. Pharo reads the file back (via `GT4A:` on FS-UAE; over the protocol on real hardware).
  - Known, accepted limit (no design can remove it): a program that takes the hardware (`Forbid`/`Disable`, DMA off) also freezes the monitor — no interrupts means no serial/TCP service, no scheduling means the monitor task never runs. The monitor goes mute for the takeover window and recovers afterwards thanks to the v2 framing (`$A5` hunt + idempotent-command retries). Worth documenting in the book page as a lesson in what `Forbid`/`Disable` really mean.
- [x] Retire `gt4amiga-watcher` (script, trigger file, done marker, serial capture): `GT4FSUAERunner run:` now drives runs through `GT4AmigaMonitorClient` (`waitForMonitorTimeout:` ping, deploy without trigger, `executeProgram`, mailbox wait, `capturedOutput`)
- [x] Auto-start the monitor at boot: `user-startup` now launches the monitor (guarded by `IF EXISTS`, so a fresh checkout without a deployed binary boots cleanly). The `S:User-Startup` inside the existing HDF was rewritten *by a program executed through opcode `X` itself* — no Amiga Shell typing involved. **Verified (2026-07-11)**: cold boot from the updated HDF auto-started the monitor and `GT4FSUAERunner run:` returned a program's output end-to-end with no watcher anywhere.
- [x] Document the wire protocol in this README (frame layout, opcode table with payloads, NAK/retry semantics, idempotency rules, resynchronisation) — see "Monitor wire protocol (v2, framed)" above; implementation detail stays in the `GT4AmigaMonitorClient` class comment and the monitor source.

### Later

- [ ] Software restore after a Copper takeover (`GfxBase->LOFlist` → `COP1LC`) instead of rebooting
- [ ] Test the TCP transport on real hardware (A500 + PiStorm/Emu68 + WiFi)
- [ ] Monitor resilience on `SER:`: reopen the port after a read error instead of exiting (the TCP transport already survives client loss via its accept loop)
- [ ] Syntax highlighting for 68000 assembly in the snippet editor
- [ ] Bare-metal mode: bootable ADF generation for hardware-direct demos
- [ ] Real hardware target via [A314](https://github.com/niklasekstrom/a314)
- [ ] Copper list visualiser and custom-chip register reference

## License

MIT — see [LICENSE](LICENSE).
