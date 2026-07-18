<div align="right"><a href="SETUP.md">🇬🇧 English</a> · <a href="SETUP.es.md">🇪🇸 Español</a></div>

# Setup — Amiga ChipLab

[← Back to README](../README.md)

Everything you need to get the platform running against FS-UAE (or real hardware). The codebase, packages and classes are named **GT4Amiga**; "Amiga ChipLab" is the platform.

## Prerequisites

| Tool | Notes |
|------|-------|
| [GToolkit](https://gtoolkit.com) | The Pharo-based live environment that hosts the platform |
| `vasmm68k_mot` | Motorola-syntax 68k assembler. Build from [source](http://sun.hasenbraten.de/vasm/) or install via your package manager |
| [FS-UAE](https://fs-uae.net) | Amiga emulator (for the emulator target) |
| Kickstart ROM | A legal ROM dump (1.3 recommended). Cloanto/Amiga Forever encrypted ROMs (`.rom` + `rom.key`) are supported |
| Workbench HDF | An AmigaOS hard-drive image with `c/Run` (any stock Workbench has it) |

## 1. ROM and disk images

Place your files in the project directories (both are git-ignored):

```
rom/
├── kick13.rom        ← Kickstart ROM (any name, .rom extension)
└── rom.key           ← Required only for Cloanto/Amiga Forever encrypted ROMs
hdf/
└── workbench.hdf     ← Workbench hard-drive image (any name, .hdf extension)
```

`GT4AmigaConfiguration` auto-detects the first `.rom` file in `rom/` and the first `.hdf` file in `hdf/`. No manual path configuration needed.

## 2. FS-UAE config — important note

GT4Amiga writes the complete FS-UAE configuration to `~/.config/fs-uae/fs-uae.conf` every time you press **Run on FS-UAE**. This is the only path that works reliably.

**Why not a session config file?** FS-UAE has two initialisation phases:

1. **Early init** — reads `~/.config/fs-uae/fs-uae.conf` and processes all hardware options: `kickstarts_dir`, `hard_drive_*`, memory, model.
2. **Late init** — reads the file passed via `--config=`. By this point hardware setup is already done; most options (hard drives, kickstarts dir) are silently ignored.

Passing our config with `--config=` therefore causes hard drives and the Kickstart directory to be ignored, and FS-UAE falls back to the built-in AROS ROM with no disks. Writing directly to `~/.config/fs-uae/fs-uae.conf` ensures every setting takes effect.

> **Side effect**: GT4Amiga replaces this file on every run. If you use FS-UAE for other projects, back up your existing `~/.config/fs-uae/fs-uae.conf` first, or use a dedicated Linux user for GT4Amiga work.

> **Cloanto/Amiga Forever ROMs**: These are encrypted (`AMIROMTYPE1` header). Place `rom.key` (from your Amiga Forever installation) in `rom/` alongside the `.rom` file. FS-UAE decrypts them automatically when it scans `kickstarts_dir`.

## 3. vasm

`GT4AmigaConfiguration` searches for `vasmm68k_mot` in these locations, in order:

1. `/home/<you>/local/vasm/vasmm68k_mot`
2. `/usr/local/bin/vasmm68k_mot`
3. `/usr/bin/vasmm68k_mot`
4. Bare name `vasmm68k_mot` (PATH lookup)

Build from [source](http://sun.hasenbraten.de/vasm/) and place the binary in any of the above locations.

## 4. Amiga-side monitor autostart

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

## 5. The monitor (program execution + live memory / library-call access)

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

See the class comment on `GT4AmigaMonitorClient` for the full protocol and the design dead-ends already ruled out (notably: `LockPubScreen()` is Kickstart 2.0+ only and does not exist on the Kickstart 1.3 target this project uses). The wire protocol itself is documented in [PROTOCOL.md](PROTOCOL.md).

> **Resolved (2026-07-09)**: an earlier version of this section documented a "systemic crash" when `callLibrary:lvo:...` targeted `intuition.library`/`graphics.library`. Root-caused and fixed — it was three 68k register-hygiene bugs in `gt4amiga-monitor.s` (mutating `a6` before the `jsr` instead of using indexed addressing; `move.b` into an uncleared `d4` producing gigantic byte counts; loading `a0` before a `dos.library/Read()` call that clobbers it). All four primitives are now verified end-to-end, including `MoveScreen` and `SetRGB4` calls and a write-then-readback memory test. The full post-mortem — including the Python-over-TCP probe technique that isolated the bugs in minutes after hours of in-image debugging — is in the class comment on `GT4AmigaMonitorClient`.
