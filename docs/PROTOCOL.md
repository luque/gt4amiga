<div align="right"><a href="PROTOCOL.md">🇬🇧 English</a> · <a href="PROTOCOL.es.md">🇪🇸 Español</a></div>

# Monitor wire protocol (v2, framed) — Amiga ChipLab

[← Back to README](../README.md)

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
| `B` `$42` block read | `[addr:4][len:2]` — len 1..4096 | the `len` bytes read |
| `P` `$50` block write | `[addr:4][len:2][data × len]` — len 1..4096 | empty (ack) |
| `C` `$43` call library | `[lib:1][pad:1][lvo:2 signed][a0:4][a1:4][d0:4][d1:4][d2:4][d3:4]` | `d0` after the call (4 bytes) |
| `S` `$53` screen pointer | none | `IntuitionBase->FirstScreen` (4 bytes) |
| `X` `$58` execute program | none | execution-mailbox address (4 bytes), or `0` if nothing was launched |
| `Q` `$51` quit | none | empty; the monitor then exits |

`lib` for CALL: `0` = exec, `1` = dos.library, `2` = intuition.library, `3` = graphics.library (bases opened once at monitor startup). `lvo` is the signed 16-bit library vector offset (e.g. FindTask = `-294`).

`B`/`P` carry at most 4096 bytes per frame (the monitor's buffer bound; clients chunk larger transfers). The monitor snapshots the region into an internal buffer, so a `B` response's data and checksum come from one coherent read, and a `P` only copies to the destination *after* the checksum verifies — a corrupt frame NAKs without having touched memory. Both copy byte-wise: they are for RAM (framebuffers, copper lists, sprites); custom chip registers require word-size accesses — use `R`/`W` for those.

`X` loads `GT4A:incoming/program` and runs it as a separate AmigaDOS process with its `Output()` captured to `GT4A:outgoing/output`; the monitor keeps serving commands meanwhile. Completion is polled by the host through ordinary `R` reads of the mailbox: `+0` state byte (`0` never ran, `1` running, `2` done, `3` launch error), `+4` return-code long (the program's final `d0`, valid at state 2). An `X` while state is `1`, or whose `LoadSeg`/`CreateProc` fails, answers `0`.

**Retry rules** (what the Pharo client implements, and any client should):

- **NAK** → resend, always. Nothing ran on the Amiga side.
- **Silence or a corrupt response** → execution is *uncertain*: the command may have run and only its response been lost. Retry only the idempotent commands — `R`, `W`, `S` — and never `C` or `X` (a library call or a program launch could execute twice).
- A fully silent retry round usually means the connection itself is dead (e.g. the peer closed and the socket sits in CLOSE-WAIT): force a reconnect and try once more.

**Resynchronisation**: the monitor's parser *hunts* the `$A5` sync byte — after any mutilated frame it discards bytes until the next `$A5`, so it recovers by itself; a `$A5` inside a payload is harmless in normal operation because frame bodies are read by length, not scanned. A `W` whose `size` byte is not 1, 2 or 4 is discarded outright (realign, no NAK) — a corrupt size must never become a read count. On the wire the serial layer must be free of XON/XOFF flow control, or `$11`/`$13` payload bytes will be eaten in transit — see the one-time serial setup note in [SETUP.md](SETUP.md).
