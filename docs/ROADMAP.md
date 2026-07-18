<div align="right"><a href="ROADMAP.md">🇬🇧 English</a> · <a href="ROADMAP.es.md">🇪🇸 Español</a></div>

# Roadmap — Amiga ChipLab

[← Back to README](../README.md)

Amiga ChipLab is a **platform**: the monitor + wire protocol, the Pharo client and FS-UAE runner, the assembler integration, and — above all — a growing library of **live models of the custom hardware** (registers, the machine, and one model per chip subsystem) with their live views and example Lepiter pages. Didactic **books** (a living Amiga Hardware Reference, a game-programming book, a general 68000 course) are built *on top* of these models and live in their own repositories; this roadmap is the platform's.

## Done

- [x] 68000 assembler integration (`vasmm68k_mot`)
- [x] FS-UAE runner with shared-directory file exchange and serial capture
- [x] Custom `amiga68kSnippet` type for Lepiter pages
- [x] Auto-detection of vasm, Kickstart ROM and Workbench HDF paths
- [x] First example notebooks: assembler primer + AmigaOS Hello World
- [x] Taking and releasing hardware control (`Forbid`/`Disable`, DMA)
- [x] Bridge server (`GT4AmigaMonitorClient`): live memory/library-call access over SER: — all four primitives verified end-to-end, including `intuition.library`/`graphics.library` calls (`MoveScreen`, `SetRGB4`)
- [x] Bridge server example notebook: live reads, `SetRGB4` color change, GToolkit slider driving the background color in real time
- [x] Copper split example notebook: hand-built Copper list in live chip RAM, slider moving the split line
- [x] Framed monitor protocol (v2): sync byte `$A5` + XOR checksum + NAK/retry semantics, so serial byte loss is a detectable, retryable error instead of silent memory corruption; the monitor re-syncs itself after any corrupt frame
- [x] Monitor transport abstraction: TCP server via `bsdsocket.library` (real hardware over the network) with `SER:` fallback (FS-UAE), auto-selected at startup; stack discipline fixed so link-loss exits are clean from any call depth

### One resident program (the monitor absorbs the watcher)

Goal: the monitor becomes the *only* resident program on the Amiga side, replacing the polling watcher script. This removes the SER: contention between watcher and monitor, the 1-second trigger-polling latency, and the trigger/done-marker race — and the one-shot run pipeline inherits the framed protocol's checksum/retry reliability for free. It also works unchanged over the TCP transport on real hardware, where the watcher's `>SER:` redirect does not exist.

- [x] New monitor opcode `X` (execute): load `GT4A:incoming/program` with `LoadSeg()` and launch it as a **separate process** via `CreateProc()` (dos.library V34 — present on Kickstart 1.3), not an in-process `jsr`. The monitor acks immediately and returns to its command loop, so `R`/`W`/`C` keep working *while the program runs* — live inspection of a running program from GToolkit. **Verified end-to-end (2026-07-11)**: 12 `R` + 12 `S` commands serviced while a 5-second test program ran, return code and captured output both correct, immediate relaunch OK. Design notes:
  - A small stub runs inside the child process: it opens the output-capture file and installs it as its own `pr_COS` (a `CreateProc()`'d process has no CLI context, so `Output()` would return 0 otherwise), `jsr`s into the loaded seglist, then writes a completion flag + return code at a known address before exiting.
  - Completion is polled by the host (via `R` on the flag address) — Kickstart 1.3 has no process-death notification.
  - Program output goes to a capture file, never raw onto the wire.
  - Known, accepted limit (no design can remove it): a program that takes the hardware (`Forbid`/`Disable`, DMA off) also freezes the monitor — no interrupts means no serial/TCP service. The monitor goes mute for the takeover window and recovers afterwards thanks to the v2 framing.
- [x] Retire `gt4amiga-watcher`: `GT4FSUAERunner run:` now drives runs through `GT4AmigaMonitorClient` (`waitForMonitorTimeout:` ping, deploy without trigger, `executeProgram`, mailbox wait, `capturedOutput`)
- [x] Auto-start the monitor at boot via `user-startup` (guarded by `IF EXISTS`). **Verified (2026-07-11)**: cold boot auto-started the monitor and `GT4FSUAERunner run:` returned a program's output end-to-end with no watcher anywhere.
- [x] Document the wire protocol — see [PROTOCOL.md](PROTOCOL.md).

### Live hardware model — the AHRM's subject matter as live objects

Goal: model the *subject matter* of the Amiga Hardware Reference Manual as live objects — **model objects with multiple `gtViews`** that both *reflect* and *act on* custom-chip state through the monitor, plus **live figures** (diagrams drawn from the machine's actual state, not static images) and thin example pages. Books that *teach* this material are separate repositories that compose these models; here we build the models, their views, and example notebooks. (The AHRM's text is copyrighted: its chapter structure and register tables serve as skeleton and reference data, but explanations and figures are written from scratch — and the figures come out *better*, because they are alive.)

- [x] Block-transfer opcodes in the monitor (`B`/`P`, up to 4096 bytes per frame, client-side chunking for unlimited sizes). **Verified end-to-end (2026-07-11)** with an 8 KB write-then-readback (including `$A5`/`$11`/`$13` payload bytes) and the example notebook "Lectura en Bloque — La Pantalla de Workbench dentro del Libro", which block-reads the live Workbench bitplanes and composes them into an image inside the notebook (~5 KB/s over the FS-UAE serial bridge).
- [x] `GT4Amiga-Hardware` model package, founded on the chip register + bit-field model: 57 registers encoded as objects (`#read`/`#write`/`#setClear`/`#strobe` semantics, decoded fields — verified against `hardware/custom.i`, `dmabits.i`, `intbits.i`, `adkbits.i`). Each register knows *how its current value is knowable*: directly readable, through its read counterpart (DMACON via DMACONR), derived from the OS (COLORxx ask the ViewPort ColorMap via `GetRGB4`), or shadow of the last write. **Verified live (2026-07-12)**: full-catalog refresh in 3.2 s, DMACONR `$03F0`, palette derived correctly, VHPOSR moving between reads, BPLEN toggle with readback.
- [x] Interactive DMACON/INTENA control panel (Bloc, `GT4Amiga-Hardware-UI`): click-to-toggle bits on top of the register model. Clicks only enqueue; a background worker performs the SET/CLR write, reads back and announces, and polls every 2 s while idle. Link-critical bits (INTEN, RBF, TBE, PORTS, and now VERTB/EXTER) are shown but locked; BBUSY/BZERO are read-only LEDs; the worker stops when the element leaves the scene graph. **Verified live (2026-07-14)**: BPLEN toggled through the click path with readback and zero orphan processes — plus the example notebook "El Panel de Control".
- [x] `GT4AmigaMachine` root model + global views: a clickable block diagram (68000, Agnus, Denise, Paula, CIAs, chip/slow RAM, ROM — DMA arrows lit from the live DMACON) and a memory map (regions with windowed hexdumps). Physical and functional decompositions as alternate views. Live chip/fast free-memory gauges via `C` to `exec/AvailMem`. **Verified live (2026-07-14)**: gauges read ExecBase/436 KB chip free, ROM dump opens with Kickstart's `$1111` magic, disabling BPLEN+SPREN darkens exactly the Denise arrow — plus the example notebook "La Máquina — Un Diagrama de Bloques Vivo".
- [x] The AHRM's centerpiece live figure (6-9): the DMA time-slot-per-scanline diagram as a live element — 227 color clocks, the fixed odd-slot allocations, and the bitplane fetch window from the live DDFSTRT/DDFSTOP with the figure 6-11/6-12 fetch order, up to the live BPU count. This forced the model to answer *how is a write-only display register knowable?*: BPLCON0/1/2, DDF/DIW and the modulos now derive their value from the **live copper list** (`GfxBase->LOFlist`). **Verified live (2026-07-15)**: BPLCON0 derives `$A200`, DDF `$3C-$D0` gives 78 bitplane slots, a BPLEN toggle pales all bitplane slots and back — plus the example notebook "Los Time Slots de DMA".
- [x] A `Diagram` inspector view on every register: the AHRM-style bit diagram as a live figure that both reflects and, **where the model says it is safe, writes**. Writability is gated by a **write-safety policy on the model** (`GT4AmigaChipRegister>>writeSafetyOf:`, the single source of truth the Control Panel shares): `#writable` (clickable), `#transient` (copper-owned, amber), `#linkCritical`/`#systemCritical` (red, locked — a live poke of INTREQ or INTENA VERTB/EXTER can hold a task), `#readOnly`, `#protocol`. **Verified live (2026-07-17)**: AUD0EN toggled through the diagram (`$03F0`→`$03F1`→`$03F0`) with hardware readback; locked/transient bits render red/amber; zero orphan workers.
- [ ] Replace the per-view polling loops with one shared observer, and add a generic "live hardware" snippet type (evaluates to a model object, embeds its refreshing inspector). Directly targets the concurrent-reader link-jam failure mode. Design: a **single serial gateway** owned by the catalog (`GT4AmigaChipRegisters>>observer`, a `GT4AmigaHardwareObserver`) is the only process that reads the machine; views declare what they need (`watch:for:` / `unwatch:`) and repaint from cache on the announcement — outside a Lepiter page each view subscribes on scene-graph enter/leave, inside a page a page-level observer aggregates the page's views into one grouped subscription with its own lifecycle and controls (pause/resume/step/cadence). Both feed the same gateway, so page and non-page views never contend for the socket.
  - [x] The shared serial gateway (`GT4AmigaHardwareObserver`): de-duplicated union reads, serialized writes, one background loop, generation-stamped, idles when nothing is watched. **Verified live (2026-07-18)**: the migrated Diagram subscribes/toggles/detaches cleanly (`$03F0`→`$03F1`→`$03F0`), and 3 views over 2 distinct registers run under 1 reader process with DMACON read once, zero orphans after teardown.
  - [x] Pilot migration: `GT4AmigaRegisterDiagramElement` now uses the gateway instead of its own worker.
  - [ ] Migrate the remaining views (Control Panel, DMA timeline, block diagram) to the gateway.
  - [ ] Page-level observer + the generic live-hardware snippet type.
- [ ] Chip-state snapshot/restore so every example cleans up after itself and pages are re-runnable top to bottom.

### Live models for each chip subsystem (platform)

Each = model + views + example notebook. These are **platform** models the books will compose.

- [ ] **Copper**: `CopperList` model (assemble/disassemble MOVE/WAIT/SKIP ↔ words), raster-timeline view (WAITs on a frame strip, draggable), and disassembly of Workbench's own list from `GfxBase->LOFlist`. (Two pieces already landed ahead of the model: the catalog reads the live list for its write-only register derivations, and the software restore after a Copper takeover — `LOFlist` → `COP1LC`, then `FreeMem` — is built and demonstrated in the example notebooks "Copper Bars — Rasterbars de la Demoscene" and "Copper Bars Nativas", **verified on screen 2026-07-16**.)
- [ ] **Playfield / bitplanes**: framebuffer viewer — read BPLxPT planes + palette over block transfer, compose in Pharo, render "what the Amiga sees" inside the notebook; modulo and BPLCON1 scroll interactives, dual-playfield priorities.
- [ ] **Sprites**: pixel editor in GT (16×N, 2bpp) writing sprite data to chip RAM live — draw in the notebook, watch it float over Workbench; drag positioning, decoded VSTART/HSTART/attach.
- [ ] **Blitter**: minterm truth-table builder (pick A/B/C combinations → LF byte), before/after memory-as-bitmap views around a live blit, `OwnBlitter`/`DisownBlitter` discipline as the sharing lesson.
- [ ] **Paula / audio**: waveform editor → chip RAM, period/volume sliders — immediate feedback you can *hear*.

## Later

- [ ] Test the TCP transport on real hardware (A500 + PiStorm/Emu68 + WiFi)
- [ ] Monitor resilience on `SER:`: reopen the port after a read error instead of exiting (the TCP transport already survives client loss via its accept loop)
- [ ] Syntax highlighting for 68000 assembly in the snippet editor
- [ ] Bare-metal mode: bootable ADF generation for hardware-direct demos
- [ ] Real hardware target via [A314](https://github.com/niklasekstrom/a314)

## Books built on Amiga ChipLab (separate repositories)

- [ ] **The living Amiga Hardware Reference** — the AHRM's subject matter taught chapter by chapter, composing ChipLab's live register/machine/chip models and figures for the clearest possible didactics.
- [ ] **Amiga game programming** — a hands-on game built up over chapters.
- [ ] **68000 assembly** — a general course on the CPU, using the assemble-and-run loop and live memory/register inspection.
