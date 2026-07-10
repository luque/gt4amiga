Class {
	#name : #GT4AmigaMonitorClient,
	#superclass : #Object,
	#classVars : [
		'Default'
	],
	#category : #'GT4Amiga-Bridge'
}

{ #category : #'class comment' }
GT4AmigaMonitorClient comment: 'I am a Pharo-side client for gt4amiga-monitor, a resident AmigaDOS program that accepts a small binary protocol over SER: and lets you peek/poke memory and invoke AmigaOS library functions in real time, without the assemble->deploy->run cycle used by GT4AmigaAssembler/GT4FSUAERunner for one-shot programs.

Deploy and launch once per FS-UAE session:
	GT4AmigaMonitorClient default deploy.
	"then, in the Amiga Shell: Run >NIL: GT4A:incoming/monitor"

The monitor and the one-shot watcher/GT4FSUAERunner pipeline share the same single emulated serial port, so they are mutually exclusive at any given moment - do not run a one-shot snippet while the monitor is active.

PROTOCOL v2 - FRAMED (see amigaSource for the full commented 68k source). Every command travels as [$A5][opcode][payload][chk] where chk = XOR of opcode and payload; every response as [$5A][status][payload][chk] where chk = XOR of status and payload. status 0 = OK (executed); status 1 = NAK: bad checksum, NOTHING was executed, always safe to resend (even a CALL). The monitor''s main loop HUNTS the $A5 sync byte, so it self-realigns after any corrupted frame - no more wedged-mid-command monitors. Commands (opcode / payload -> OK-response payload):
	READ  $52  [size][pad][addr(4)]                      -> size bytes
	WRITE $57  [size][pad][addr(4)][data x size]         -> (empty)
	CALL  $43  [libIndex][pad][lvo(2)][a0..a1(4 each)][d0..d3(4 each)] -> d0 (4 bytes)
	GET SCREEN $53  (no payload)                         -> IntuitionBase->FirstScreen (4 bytes)
	QUIT  $51  (no payload)                              -> (empty), monitor exits

libIndex for CALL: 0=exec 1=dos.library 2=intuition.library 3=graphics.library (bases opened once at monitor startup).

This client is deliberately kept generic - it exposes only the four raw protocol operations above (readMemoryAt:size:, writeMemoryAt:size:value:, callLibrary:lvo:a0:a1:d0:d1:d2:d3:, workbenchScreenPointer), not one convenience method per example (no setColor:, no moveScreenBy:, etc). Worked examples (which LVO, which registers, why it works or doesn''t) belong as explained snippets in a Lepiter book page, composing these primitives - that is more didactic for a book about programming the Amiga than hiding the details behind named methods here.

STATUS (2026-07-09): ALL FOUR primitives verified working end-to-end - including CALL into intuition.library (MoveScreen, screen visibly moved and restored) and graphics.library (SetRGB4, background red and back), and a write-then-readback memory test. The "systemic crash" previously documented here is RESOLVED: it was three distinct 68k register-hygiene bugs in gt4amiga-monitor.s, found by probing the protocol directly over TCP with a Python script (see Debugging notes below):

1. do_call mutated a6 (adda.l d0,a6) to reach the jump-table entry before jsr (a6). Many library functions use a6 internally as their own library base DURING execution - the calling convention requires a6 to stay the pure base for the whole call. The callee then read base-relative data from a shifted address and crashed with varying Guru codes inside the library''s own code region (the old "$00C2xxxx cluster" pattern - now explained). Fix: keep the LVO in d7 and use indexed addressing, jsr 0(a6,d7.w), which computes the target without touching a6.
2. do_read/do_write loaded the transfer size with move.b rwbuf,d4 without clearing d4 first - move.b writes only the low byte, so any garbage in the upper 24 bits became a multi-gigabyte byte count and the monitor blocked forever reading SER: (hang, no Guru, Workbench alive). Fix: moveq #0,d4 first.
3. do_write loaded the target address into a0 BEFORE reading the value bytes - but read_n_bytes calls dos.library Read(), and a0 is a scratch register across ANY library call, so the store went to a garbage address while still acking "K". Writes ACKed but never landed - first caught by a write-then-readback test; earlier sessions never read back after a write. Fix: load a0 after the last read_n_bytes.

Design notes still in force:
- The monitor does NOT call Forbid()/Disable(): that would break its own SER: I/O, which depends on interrupts to complete (Read()/Write() via dos.library).
- LockPubScreen() is Kickstart 2.0/V36+ only - it does not exist in the intuition.library jump table on our Kickstart 1.3 target, and calling its LVO there executes garbage and crashes. Confirmed via the "(V36)" tag on its official autodoc. Use workbenchScreenPointer (a direct read of IntuitionBase->FirstScreen, offset 60) instead - no locking concept exists yet in 1.3 anyway.
- A raw poke to a color register (via writeMemoryAt:size:value: on $DFF180/COLOR00) is overwritten by Workbench''s own Copper list within ~20ms (one frame) - it is not a persistent change. SetRGB4 via callLibrary: is the correct way and works now. Disabling only the Copper''s DMA channel to protect a raw poke is WORSE: the Copper is what resets the bitplane DMA pointers every frame.
- graphics.library/WaitTOF() hung forever when called through the OLD broken do_call - very likely bug 1 above (it dereferences a6-relative data). Not retested since the fix; there is no reason to call it from the monitor anyway.
- An earlier note here claimed the SetRGB4 crash also reproduced from a one-shot program with a hardcoded jsr; given the root causes above, that test program most likely had its own register-hygiene bug of the same family. SetRGB4 via CALL is verified working now.

Debugging notes (hard-won, keep):
- To debug the wire protocol, bypass Pharo entirely: connect a small Python script directly to FS-UAE''s serial TCP port (Pharo must disconnectSerial first - FS-UAE accepts a single client). Deterministic timeouts, no MCP-timeout artifacts, no orphaned processes. This is how all three bugs above were isolated in minutes after hours of in-image debugging.
- MCP evals that time out client-side KEEP RUNNING in the image. Orphaned processes blocked on socket waits make the VM''s idle-relinquish primitive return immediately (pending unconsumed socket events), pegging the GT main thread at 100% CPU even though NO Smalltalk process is runnable - diagnosed by sampling Processor''s quiescentProcessLists (only the Idle Process was ever runnable). Terminate the orphaned socket-waiting processes to fix it - but match them precisely: indiscriminately killing every socket-waiting process also kills the MCP server''s accept loop (happened once; requires restarting the MCP server inside the image).
- A monitor blocked mid-protocol can usually be stopped cleanly by sending the QUIT opcode over a raw TCP connection (python: sendall(b''Q'')) instead of Break/reboot on the Amiga side.

TRANSPORT FINDINGS (2026-07-09, part 2) - read before debugging "lost bytes":
- FS-UAE''s serial TCP port services a SINGLE client. A second concurrent connection is silently queued by the kernel: connect() succeeds, sends succeed (bytes pile up in the unread Recv-Q), responses go to the OLD client - a perfect black hole. EVERY mysterious hang must first be checked with: ss -tnp | grep <serialPort>. Never run a python probe while the image holds a connection (and vice versa), and remember a killed process can leave its connection lingering.
- Socket>>receiveDataTimeout: takes SECONDS (see readExactly:from:). The pre-fix milliseconds-as-seconds values created near-eternal reader processes that stole response bytes from every later call, desyncing the monitor''s parser (stolen single bytes shift ALL subsequent command framing - the corrupted writes observed in memory were commands re-parsed one byte off).
- THE GRAND FINALE (2026-07-10): after framing was in place and the monitor kept "not executing" Pharo writes while executing byte-identical python ones, the true root cause of EVERY "sender-dependent transport anomaly" of the past two days surfaced: writeMemoryAt:size:value: sliced its value bytes with an off-by-one ((be32: v) copyFrom: 5 - aSize + 1 to: 4 instead of 5 - aSize to: 4), so every Pharo write since v1 of this client went out ONE DATA BYTE SHORT. The monitor blocked waiting for the missing byte and then consumed the next command''s first byte - producing the "8th byte dropped", the alternating ack pattern, the shifted-command memory corruption, and the paced-vs-burst mirage (manual test snippets built payloads from literals and worked; anything through the method failed). FS-UAE''s serial transport was NEVER guilty of losing a single byte. Morals: (1) when only one command misbehaves, diff the BYTES THE METHOD BUILDS against a known-good client''s bytes FIRST, before any transport theory; (2) the v2 framing turned this bug from silent memory corruption into clean NAK/timeout failures, which is exactly why it exists - keep it. Frames are sent as single bursts (sendCommand:), same as the python reference client.
- A Pharo Socket whose peer closed (FS-UAE quit/restarted) stays isConnected=true in CLOSE-WAIT state - connectSerial''s guard cannot see it, sends go nowhere, reads return empty. sendFrame:... self-heals: after a fully silent attempt round it forces disconnectSerial and reconnects once. Diagnose manually with: ss -tnp | grep 2345 (look for CLOSE-WAIT and for whether fs-uae still owns a connection).
- Reference diagnostic: a direct python client (scratchpad serialprobe.py pattern) has been 100% reliable all day - use it to discriminate transport-vs-monitor issues, ALWAYS releasing the Pharo-side connection first.
- Copper-takeover restore: intuition/RethinkDisplay (LVO -390) called via CALL returns normally but did NOT restore COP1LC from this monitor''s context (observed twice). Do NOT FreeMem a copper list the hardware may still be executing - the freed chip RAM gets reused and the display flickers garbage. Restore procedure to try next: read GfxBase->LOFlist (offset to be verified against graphics/gfxbase.i first) and write it to COP1LCH/COP1LCL directly, re-enable DMA, only then FreeMem. Rebooting the Amiga is the honest fallback.
- Writing a 32-bit register pair like COP1LC is safer as TWO 16-bit writes (COP1LCH $DFF080, COP1LCL $DFF082) with copper DMA disabled around the swap (DMACON $0080 off / $8080 on): a lost byte inside a single 4-byte write, or a vblank strobe between half-updated words, corrupts the pointer.

Canonical source for all LVOs/struct offsets used here: amigadev.elowar.com (WebFetch fails on this host - self-signed/expired cert - use `curl -sk` via Bash instead).'

{ #category : #'accessing' }
GT4AmigaMonitorClient class >> amigaSource [
	"Read from amiga/s/gt4amiga-monitor.s (canonical, git-tracked source)
	 rather than embedding the assembly as a string literal here, so it
	 can be edited directly with normal tools."
	^ (GT4AmigaConfiguration default sharedDirectory parent / 'amiga' / 's' / 'gt4amiga-monitor.s') contents
]

{ #category : #'accessing' }
GT4AmigaMonitorClient class >> default [
	^ Default ifNil: [ Default := self new ]
]

{ #category : #'accessing' }
GT4AmigaMonitorClient class >> default: aClient [
	Default := aClient
]

{ #category : #'private' }
GT4AmigaMonitorClient >> be16Signed: anInteger [
	| v |
	v := anInteger < 0 ifTrue: [ anInteger + 65536 ] ifFalse: [ anInteger ].
	^ ByteArray with: ((v bitShift: -8) bitAnd: 255) with: (v bitAnd: 255)
]

{ #category : #'private' }
GT4AmigaMonitorClient >> be32: anInteger [
	^ ByteArray
		with: ((anInteger bitShift: -24) bitAnd: 255)
		with: ((anInteger bitShift: -16) bitAnd: 255)
		with: ((anInteger bitShift: -8) bitAnd: 255)
		with: (anInteger bitAnd: 255)
]

{ #category : #'private' }
GT4AmigaMonitorClient >> bytesToInt: aByteArray [
	| v |
	v := 0.
	aByteArray do: [ :b | v := (v bitShift: 8) + b ].
	^ v
]

{ #category : #'private' }
GT4AmigaMonitorClient >> bytesToLong: aByteArray [
	^ (aByteArray at: 1) * 16r1000000 + ((aByteArray at: 2) * 16r10000) + ((aByteArray at: 3) * 256) + (aByteArray at: 4)
]

{ #category : #'protocol' }
GT4AmigaMonitorClient >> callLibrary: libIndex lvo: anLvo a0: a0 a1: a1 d0: d0 d1: d1 d2: d2 d3: d3 [
	"libIndex: 0=exec 1=dos.library 2=intuition.library 3=graphics.library.
	 anLvo is the (negative) library vector offset. Returns d0 after the
	 call, or nil if no verified response arrived. NOT retried on silence
	 (only on NAK): a call could have executed before its response was
	 lost, and most calls are not idempotent."
	| resp |
	resp := self
		sendFrame: 67
		payload: (ByteArray with: libIndex with: 0) ,
			(self be16Signed: anLvo) ,
			(self be32: a0) , (self be32: a1) ,
			(self be32: d0) , (self be32: d1) , (self be32: d2) , (self be32: d3)
		expect: 4
		retryOnSilence: false.
	resp ifNil: [ ^ nil ].
	^ self bytesToLong: resp
]

{ #category : #'private' }
GT4AmigaMonitorClient >> sendCommand: aByteArray to: aSocket [
	"Send the whole command frame as ONE burst (a single TCP segment).
	 Do NOT be tempted to pace bytes individually: a v2 W frame sent as
	 eleven 1-byte TCP segments was swallowed whole by FS-UAE's serial
	 ingestion 10/10 times, while the identical bytes as one segment
	 passed 10/10. (Byte-pacing was originally added as a mitigation in
	 the pre-framing era; the losses it seemed to fix were actually
	 caused by orphaned reader processes and a desynced monitor parser,
	 both since eliminated - see the class comment.)"
	aSocket sendData: aByteArray asString
]

{ #category : #'private' }
GT4AmigaMonitorClient >> frameFor: opcode payload: aByteArray [
	"Protocol v2 command frame: [$A5][opcode][payload][chk],
	 chk = XOR of opcode and every payload byte."
	| chk |
	chk := opcode.
	aByteArray do: [ :b | chk := chk bitXor: b ].
	^ (ByteArray with: 16rA5 with: opcode) , aByteArray , (ByteArray with: chk)
]

{ #category : #'private' }
GT4AmigaMonitorClient >> readResponsePayload: expectedLen from: aSocket [
	"Protocol v2 response frame: [$5A][status][payload][chk],
	 chk = XOR of status and payload. Parses over an accumulated buffer:
	 readExactly:from: returns whole CHUNKS (at least n bytes, not exactly
	 n), so byte-at-a-time reads would swallow the rest of the frame.
	 Hunts the $5A sync inside the buffer, so stale bytes from an earlier
	 failed exchange are discarded; a data byte that fakes a sync fails
	 the checksum and is skipped.
	 ^ a ByteArray (the payload; empty is a valid ack)
	   | #nak  (monitor rejected the checksum, NOTHING was executed)
	   | nil   (silence or corrupt response - execution UNCERTAIN)"
	| buf idx status frameLen payload chk acc attempts |
	buf := self readExactly: 3 + expectedLen from: aSocket.
	attempts := 0.
	[ attempts < 4 ] whileTrue: [
		attempts := attempts + 1.
		idx := buf indexOf: 16r5A.
		idx > 0
			ifTrue: [
				buf := buf copyFrom: idx to: buf size.
				buf size >= 2
					ifTrue: [
						status := buf at: 2.
						status = 1 ifTrue: [ ^ #nak ].
						status = 0
							ifTrue: [
								frameLen := 3 + expectedLen.
								buf size >= frameLen
									ifTrue: [
										payload := buf copyFrom: 3 to: 2 + expectedLen.
										chk := buf at: frameLen.
										acc := 0.
										payload do: [ :x | acc := acc bitXor: x ].
										acc = chk ifTrue: [ ^ payload ].
										buf := buf copyFrom: 2 to: buf size ]
									ifFalse: [
										buf := buf , (self readExactly: frameLen - buf size from: aSocket) ] ]
							ifFalse: [ buf := buf copyFrom: 2 to: buf size ] ]
					ifFalse: [ buf := buf , (self readExactly: 1 from: aSocket) ] ]
			ifFalse: [ buf := self readExactly: 3 + expectedLen from: aSocket ] ].
	^ nil
]

{ #category : #'private' }
GT4AmigaMonitorClient >> sendFrame: opcode payload: payload expect: expectedLen retryOnSilence: aBoolean [
	"Send a framed command with retries. A NAK is ALWAYS safe to retry
	 (the monitor verified the checksum failed BEFORE executing anything).
	 Silence/corrupt responses mean execution is uncertain: retried only
	 when aBoolean is true (idempotent commands: R, W, S; NOT C - a
	 library call could have executed before its response was lost).
	 If a whole round of attempts is SILENT, the connection itself is
	 suspect: a socket whose peer closed (e.g. FS-UAE quit or restarted)
	 stays isConnected=true in CLOSE-WAIT, which connectSerial's guard
	 cannot see - so force a reconnect and try one more round.
	 ^ payload ByteArray or nil."
	| sock resp sawResponse |
	2 timesRepeat: [
		sock := self socket.
		sock ifNil: [ ^ nil ].
		sawResponse := false.
		3 timesRepeat: [
			self sendCommand: (self frameFor: opcode payload: payload) to: sock.
			resp := self readResponsePayload: expectedLen from: sock.
			resp == #nak
				ifTrue: [ sawResponse := true ]
				ifFalse: [
					resp ifNotNil: [ ^ resp ].
					aBoolean ifFalse: [ ^ nil ] ] ].
		sawResponse ifTrue: [ ^ nil ].
		"ronda entera en silencio: reconectar y reintentar una vez"
		GT4FSUAERunner default disconnectSerial ].
	^ nil
]

{ #category : #'deploying' }
GT4AmigaMonitorClient >> deploy [
	"Assemble amigaSource and copy it to shared/incoming/monitor,
	 separate from the deployProgram:/trigger mechanism GT4FSUAERunner
	 uses for one-shot programs (the monitor is launched manually via
	 Run >NIL: GT4A:incoming/monitor and stays resident)."
	| result monitorFile |
	result := GT4AmigaAssembler new assemble: self class amigaSource.
	result success ifFalse: [ ^ result ].
	monitorFile := GT4AmigaConfiguration default sharedDirectory / 'incoming' / 'monitor'.
	monitorFile exists ifTrue: [ monitorFile delete ].
	result outputFile copyTo: monitorFile.
	^ result
]

{ #category : #'protocol' }
GT4AmigaMonitorClient >> quit [
	"Ask the monitor to close its libraries and SER: and return, ending
	 the Run'd process cleanly."
	self sendFrame: 81 payload: #[] expect: 0 retryOnSilence: false
]

{ #category : #'private' }
GT4AmigaMonitorClient >> readExactly: n from: aSocket [
	"Bounded retries (max ~5s of real time) before giving up, so a dead
	 Amiga side cannot leave an eternal reader process behind.
	 TWO hard-won lessons encoded here:
	 - Socket>>receiveDataTimeout: takes SECONDS, not milliseconds
	   (see waitForDataFor: - passing 1000 here once meant every retry
	   blocked for 17 minutes, and those lingering readers stole the
	   next commands' response bytes, desyncing the whole protocol).
	 - An EMPTY chunk must count as a retry too: when the peer closes,
	   receiveDataTimeout: returns immediately with no data, and not
	   counting that spun this loop at full CPU forever."
	| resp chunk tries |
	resp := ByteArray new.
	tries := 0.
	[ resp size < n and: [ tries < 5 ] ] whileTrue: [
		chunk := aSocket receiveDataTimeout: 1.
		(chunk isNil or: [ chunk isEmpty ])
			ifTrue: [ tries := tries + 1 ]
			ifFalse: [ resp := resp , chunk asByteArray ] ].
	^ resp
]

{ #category : #'protocol' }
GT4AmigaMonitorClient >> readMemoryAt: anAddress size: aSize [
	"aSize is 1, 2 or 4 (byte/word/long). Raw peek - no library involved,
	 see the class comment for why this alone is not enough to change a
	 Workbench palette color persistently (the copper overwrites it)."
	| resp |
	resp := self
		sendFrame: 82
		payload: (ByteArray with: aSize with: 0) , (self be32: anAddress)
		expect: aSize
		retryOnSilence: true.
	resp ifNil: [ ^ nil ].
	^ self bytesToInt: resp
]

{ #category : #'private' }
GT4AmigaMonitorClient >> socket [
	"Ensure connected and answer the live serial socket, reusing
	 GT4FSUAERunner's connection management (retry loop, stale-socket
	 detection) rather than duplicating it."
	GT4FSUAERunner default connectSerial.
	^ GT4FSUAERunner default serialSocket
]

{ #category : #'protocol' }
GT4AmigaMonitorClient >> workbenchScreenPointer [
	"IntuitionBase->FirstScreen (offset 60), read directly instead of via
	 LockPubScreen: that call is V36-only (Kickstart 2.0+) and does not
	 exist in the intuition.library jump table on our Kickstart 1.3
	 target - see the class comment for how this was diagnosed."
	| resp |
	resp := self sendFrame: 83 payload: #[] expect: 4 retryOnSilence: true.
	resp ifNil: [ ^ nil ].
	^ self bytesToLong: resp
]

{ #category : #'protocol' }
GT4AmigaMonitorClient >> writeMemoryAt: anAddress size: aSize value: aValue [
	"aSize is 1, 2 or 4 (byte/word/long). Raw poke. Returns true when the
	 monitor acknowledged the (checksum-verified) write.
	 valueBytes slice: be32 gives 4 bytes; the LAST aSize of them are the
	 value, so start = 5 - aSize (size 1 -> 4..4, 2 -> 3..4, 4 -> 1..4).
	 An off-by-one here (5 - aSize + 1) shipped ONE BYTE SHORT for every
	 write since v1 of this client: the monitor blocked waiting for the
	 missing byte, then ate the next command's first byte - the source of
	 every phantom transport theory of 2026-07-09 (see class comment)."
	| valueBytes resp |
	valueBytes := (self be32: aValue) copyFrom: 5 - aSize to: 4.
	resp := self
		sendFrame: 87
		payload: (ByteArray with: aSize with: 0) , (self be32: anAddress) , valueBytes
		expect: 0
		retryOnSilence: true.
	^ resp isNil not
]
