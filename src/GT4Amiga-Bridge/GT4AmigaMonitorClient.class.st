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

Design notes and dead ends, so they are not re-discovered the hard way:
- The monitor does NOT call Forbid()/Disable(): that would break its own SER: I/O, which depends on interrupts to complete (Read()/Write() via dos.library).
- LockPubScreen() is Kickstart 2.0/V36+ only - it does not exist in the intuition.library jump table on our Kickstart 1.3 target, and calling its LVO there executes garbage and crashes (Guru #00000003, Address Error). Confirmed via the "(V36)" tag on its official autodoc. Use workbenchScreenPointer (a direct read of IntuitionBase->FirstScreen, offset 60) instead - no locking concept exists yet in 1.3 anyway.
- A raw poke to a color register (via writeMemoryAt:size:value: on $DFF180/COLOR00) is overwritten by Workbench''s own Copper list within ~20ms (one frame) - it is not a persistent change. Disabling only the Copper''s DMA channel to stop that is WORSE: the Copper is what resets the bitplane DMA pointers every frame, so without it bitplane DMA keeps marching through RAM producing corrupted/changing graphics.
- graphics.library/SetRGB4(vp,n,r,g,b) is the correct, version-safe (no version tag on its autodoc) way to change a screen color persistently: it patches the matching MOVE instruction already present in the live Copper list. See setColor:red:green:blue: - CURRENTLY KNOWN TO CRASH shortly after changing the color (see its method comment) - under investigation.

Canonical source for all LVOs/struct offsets used here: amigadev.elowar.com (WebFetch fails on this host - self-signed/expired cert - use `curl -sk` via Bash instead).'

{ #category : #'accessing' }
GT4AmigaMonitorClient class >> amigaSource [
	^ '
; gt4amiga-monitor: bridge de lectura/escritura de memoria + llamada
; generica a funciones de libreria, en tiempo real, via SER:
;
; Comando S: devuelve IntuitionBase->FirstScreen (offset 60, confirmado
; contra el header primario intuition/intuitionbase.h + graphics/view.h:
; sizeof(struct Library)=34 + sizeof(struct View)=18 + ActiveWindow(4)
; + ActiveScreen(4) = 60). Sustituye a LockPubScreen(), que es de V36
; (Kickstart 2.0) y no existe en la tabla de intuition.library de nuestro
; Kickstart 1.3 - saltar a su LVO (-510) en 1.3 ejecuta memoria fuera de
; la tabla real y provoca un Address Error. Confirmado via autodoc oficial
; (amigadev.elowar.com), que marca LockPubScreen explicitamente "(V36)".

        SECTION code,CODE

MODE_OLDFILE equ 1005

start:
        movem.l d2-d7/a2-a6,-(sp)

        move.l  4.w,a6
        lea     dosname,a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     quit_now
        move.l  d0,a2

        lea     intuitionname,a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     close_dos
        move.l  d0,a3

        lea     graphicsname,a1
        moveq   #0,d0
        jsr     -552(a6)
        tst.l   d0
        beq     close_intuition
        move.l  d0,a4

        move.l  a2,a6
        lea     sername,a1
        move.l  a1,d1
        move.l  #MODE_OLDFILE,d2
        jsr     -30(a6)
        move.l  d0,d6
        beq     close_graphics

mainloop:
        lea     opbyte,a5
        moveq   #1,d5
        bsr     read_n_bytes
        move.b  opbyte,d7

        cmp.b   #$52,d7
        beq     do_read
        cmp.b   #$57,d7
        beq     do_write
        cmp.b   #$43,d7
        beq     do_call
        cmp.b   #$53,d7             ; S = get Workbench screen pointer
        beq     do_getscreen
        cmp.b   #$51,d7
        beq     close_ser
        bra     mainloop

do_getscreen:
        move.l  60(a3),databuf      ; IntuitionBase->FirstScreen
        lea     databuf,a5
        moveq   #4,d5
        bsr     write_n_bytes
        bra     mainloop

do_read:
        lea     rwbuf,a5
        moveq   #6,d5
        bsr     read_n_bytes
        move.b  rwbuf,d4
        move.l  rwbuf+2,a0

        cmp.b   #4,d4
        beq     rd_long
        cmp.b   #2,d4
        beq     rd_word
        move.b  (a0),databuf
        bra     rd_send
rd_word:
        move.w  (a0),databuf
        bra     rd_send
rd_long:
        move.l  (a0),databuf
rd_send:
        lea     databuf,a5
        move.l  d4,d5
        bsr     write_n_bytes
        bra     mainloop

do_write:
        lea     rwbuf,a5
        moveq   #6,d5
        bsr     read_n_bytes
        move.b  rwbuf,d4
        move.l  rwbuf+2,a0

        lea     databuf,a5
        move.l  d4,d5
        bsr     read_n_bytes

        cmp.b   #4,d4
        beq     wr_long
        cmp.b   #2,d4
        beq     wr_word
        move.b  databuf,(a0)
        bra     wr_ack
wr_word:
        move.w  databuf,(a0)
        bra     wr_ack
wr_long:
        move.l  databuf,(a0)
wr_ack:
        lea     ackbyte,a5
        moveq   #1,d5
        bsr     write_n_bytes
        bra     mainloop

do_call:
        lea     callbuf,a5
        moveq   #28,d5
        bsr     read_n_bytes

        moveq   #0,d0
        move.b  callbuf,d0
        cmp.b   #0,d0
        beq     lib_exec
        cmp.b   #1,d0
        beq     lib_dos
        cmp.b   #2,d0
        beq     lib_intuition
        move.l  a4,a6
        bra     have_base
lib_exec:
        move.l  4.w,a6
        bra     have_base
lib_dos:
        move.l  a2,a6
        bra     have_base
lib_intuition:
        move.l  a3,a6
have_base:
        move.w  callbuf+2,d0
        ext.l   d0
        adda.l  d0,a6

        move.l  callbuf+4,a0
        move.l  callbuf+8,a1
        move.l  callbuf+12,d0
        move.l  callbuf+16,d1
        move.l  callbuf+20,d2
        move.l  callbuf+24,d3

        jsr     (a6)

        move.l  d0,databuf
        lea     databuf,a5
        moveq   #4,d5
        bsr     write_n_bytes
        bra     mainloop

close_ser:
        move.l  a2,a6
        move.l  d6,d1
        jsr     -36(a6)
close_graphics:
        move.l  4.w,a6
        move.l  a4,a1
        jsr     -414(a6)
close_intuition:
        move.l  4.w,a6
        move.l  a3,a1
        jsr     -414(a6)
close_dos:
        move.l  4.w,a6
        move.l  a2,a1
        jsr     -414(a6)
quit_now:
        movem.l (sp)+,d2-d7/a2-a6
        moveq   #0,d0
        rts

read_n_bytes:
        move.l  a2,a6
readloop:
        move.l  d6,d1
        move.l  a5,d2
        moveq   #1,d3
        jsr     -42(a6)
        tst.l   d0
        ble     close_ser
        addq.l  #1,a5
        subq.l  #1,d5
        bne.s   readloop
        rts

write_n_bytes:
        move.l  a2,a6
        move.l  d6,d1
        move.l  a5,d2
        move.l  d5,d3
        jsr     -48(a6)
        rts

        SECTION data,DATA

dosname:
        dc.b    "dos.library",0
        EVEN
intuitionname:
        dc.b    "intuition.library",0
        EVEN
graphicsname:
        dc.b    "graphics.library",0
        EVEN
sername:
        dc.b    "SER:",0
        EVEN
ackbyte:
        dc.b    "K"
        EVEN

        SECTION bss,BSS

opbyte:
        ds.b    2
rwbuf:
        ds.b    6
callbuf:
        ds.b    28
databuf:
        ds.b    4
'
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
	 an orphaned process behind."
	| resp chunk tries |
	resp := ByteArray new.
	tries := 0.
	[ resp size < n and: [ tries < 10 ] ] whileTrue: [
		chunk := aSocket receiveDataTimeout: 3000.
		chunk ifNotNil: [ resp := resp , chunk asByteArray ] ifNil: [ tries := tries + 1 ] ].
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

{ #category : #'protocol' }
GT4AmigaMonitorClient >> setColor: colorIndex red: r green: g blue: b [
	"Change Workbench palette color colorIndex to (r,g,b) (each 0-15) via
	 graphics.library SetRGB4(viewport,n,r,g,b) - LVO -288, a0=viewport,
	 d0=n, d1=r, d2=g, d3=b. viewport is workbenchScreenPointer+44
	 (Screen->ViewPort, an embedded struct - see class comment).

	 KNOWN ISSUE (under investigation): this reliably changes the color
	 on screen, but has repeatedly crashed the Amiga (Guru #00000003,
	 Address Error) shortly after - suspected cause is that SetRGB4
	 patches the live Copper list while it is being read by the Copper
	 in real time, and calling it asynchronously from this background
	 process (rather than from Intuition's own input task, which has
	 some implicit synchronization) may hit that race more often."
	| screen viewport |
	screen := self workbenchScreenPointer.
	screen ifNil: [ ^ nil ].
	viewport := screen + 44.
	^ self callLibrary: 3 lvo: -288 a0: viewport a1: 0 d0: colorIndex d1: r d2: g d3: b
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
