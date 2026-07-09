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

Protocol (see amigaSource for the full commented 68k source), one command -> one response:
	READ  [$52][size][pad][addr(4)]                      -> [size bytes]
	WRITE [$57][size][pad][addr(4)][size bytes]          -> [$4B ack]
	CALL  [$43][libIndex][pad][lvo(2)][a0(4)][a1(4)][d0(4)][d1(4)][d2(4)][d3(4)] -> [d0 (4 bytes)]
	GET SCREEN [$53]                                     -> [IntuitionBase->FirstScreen (4 bytes)]
	QUIT  [$51]

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
	 call, or nil if the response did not arrive."
	| sock cmd resp |
	sock := self socket.
	cmd := (ByteArray with: 67 with: libIndex with: 0) ,
		(self be16Signed: anLvo) ,
		(self be32: a0) , (self be32: a1) ,
		(self be32: d0) , (self be32: d1) , (self be32: d2) , (self be32: d3).
	sock sendData: cmd asString.
	resp := self readExactly: 4 from: sock.
	resp size = 4 ifFalse: [ ^ nil ].
	^ self bytesToLong: resp
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
	self socket sendData: (ByteArray with: 81) asString
]

{ #category : #'private' }
GT4AmigaMonitorClient >> readExactly: n from: aSocket [
	"Bounded retries (max ~30s) - if the Amiga side never responds
	 (e.g. it crashed), give up instead of looping forever and leaving
	 an orphaned process behind. An EMPTY chunk must count as a retry
	 too: when the peer resets the connection, receiveDataTimeout:
	 returns immediately with no data, and not counting that spun this
	 loop at full CPU forever (seen live: two orphaned evals pegged the
	 GT image at 100% until terminated)."
	| resp chunk tries |
	resp := ByteArray new.
	tries := 0.
	[ resp size < n and: [ tries < 10 ] ] whileTrue: [
		chunk := aSocket receiveDataTimeout: 3000.
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
	| sock cmd resp |
	sock := self socket.
	cmd := (ByteArray with: 82 with: aSize with: 0) , (self be32: anAddress).
	sock sendData: cmd asString.
	resp := self readExactly: aSize from: sock.
	resp size = aSize ifFalse: [ ^ nil ].
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
	| sock resp |
	sock := self socket.
	sock sendData: (ByteArray with: 83) asString.
	resp := self readExactly: 4 from: sock.
	resp size = 4 ifFalse: [ ^ nil ].
	^ self bytesToLong: resp
]

{ #category : #'protocol' }
GT4AmigaMonitorClient >> writeMemoryAt: anAddress size: aSize value: aValue [
	"aSize is 1, 2 or 4 (byte/word/long). Raw poke - see readMemoryAt:size:."
	| sock cmd resp valueBytes |
	sock := self socket.
	valueBytes := (self be32: aValue) copyFrom: 5 - aSize + 1 to: 4.
	cmd := (ByteArray with: 87 with: aSize with: 0) , (self be32: anAddress) , valueBytes.
	sock sendData: cmd asString.
	resp := self readExactly: 1 from: sock.
	^ resp size = 1 and: [ (resp at: 1) = 75 ]
]
