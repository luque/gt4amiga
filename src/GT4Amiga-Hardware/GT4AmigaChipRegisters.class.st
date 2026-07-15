"
I am the catalog of the Amiga custom chip register file ($DFF000...), the foundation model of the Interactive Hardware Reference: every register is a GT4AmigaChipRegister with its AHRM access semantics, decoded bit fields, and knowledge of how its real value is knowable (readable / read-counterpart / derived from the OS / shadow). Addresses and bit numbers are verified against the canonical NDK includes (hardware/custom.i, dmabits.i, intbits.i, adkbits.i).

Usage:
	regs := GT4AmigaChipRegisters default.
	[ regs refresh ] fork.                          (re-read the machine - NEVER on the UI thread)
	(regs at: 'DMACONR') value.                     (cached, I/O-free)
	[ (regs at: 'DMACON') disable: 'BPLEN' ] fork.  (screen off - bitplane DMA)
	[ (regs at: 'DMACON') enable: 'BPLEN' ] fork.   (and back)

refresh announces GT4AmigaRegistersRefreshed through my announcer, so the registers gtView updates itself after a background refresh. The COLORxx registers derive their value from the Workbench ViewPort ColorMap via graphics GetRGB4 (the copper rewrites the color hardware every frame, so that IS the truth); the catalog caches the ColorMap pointer after the first lookup.

The write-only display registers (BPLCON0/1/2, DDFSTRT/DDFSTOP, DIWSTRT/DIWSTOP, BPL1MOD/BPL2MOD) derive their value from the LIVE COPPER LIST instead: Workbench rewrites them every frame from GfxBase->LOFlist, so the first MOVE to each register in that list IS the machine's effective display state. The catalog discovers GfxBase once per session (AllocMem a scratch name string, OldOpenLibrary, CloseLibrary right away - the monitor holds graphics.library open since startup, so the base cannot expunge - FreeMem) and snapshots the copper list through one block read, cached for a second so a full refresh scans one snapshot instead of fetching it once per derived register.

I am the model layer only: I hold no Bloc code. Inspector views come from gtView methods here and on the register/field objects, so any snippet evaluating to me (or to one register) gets the live drill-down for free.
"
Class {
	#name : #GT4AmigaChipRegisters,
	#superclass : #Object,
	#instVars : [
		'monitor',
		'registers',
		'announcer',
		'wbColorMap',
		'gfxBase',
		'copperSnapshot',
		'copperSnapshotAt'
	],
	#classVars : [
		'Default'
	],
	#category : #'GT4Amiga-Hardware'
}

{ #category : #'accessing' }
GT4AmigaChipRegisters class >> default [
	^ Default ifNil: [ Default := self new ]
]

{ #category : #'accessing' }
GT4AmigaChipRegisters class >> default: aCatalog [
	Default := aCatalog
]

{ #category : #'initialization' }
GT4AmigaChipRegisters >> initialize [
	monitor := GT4AmigaMonitorClient default.
	announcer := Announcer new.
	registers := OrderedDictionary new.
	self buildRegisters
]

{ #category : #'accessing' }
GT4AmigaChipRegisters >> monitor [
	^ monitor
]

{ #category : #'accessing' }
GT4AmigaChipRegisters >> monitor: aMonitorClient [
	monitor := aMonitorClient
]

{ #category : #'accessing' }
GT4AmigaChipRegisters >> announcer [
	^ announcer
]

{ #category : #'accessing' }
GT4AmigaChipRegisters >> registers [
	^ registers
]

{ #category : #'accessing' }
GT4AmigaChipRegisters >> at: aName [
	^ registers at: aName
]

{ #category : #'reading' }
GT4AmigaChipRegisters >> refresh [
	"Re-read every readable register from the machine and announce, so
	 subscribed views re-render. Serial I/O: call from a background
	 process, never the UI thread."
	registers valuesDo: [ :reg | reg isReadable ifTrue: [ reg read ] ].
	announcer announce: GT4AmigaRegistersRefreshed new
]

{ #category : #'reading' }
GT4AmigaChipRegisters >> workbenchColorMap [
	"ColorMap of the Workbench screen ViewPort (Screen+48 = ViewPort+4,
	 offsets verified against intuition/screens.i and graphics/view.i).
	 Cached: the screen does not move during a session."
	^ wbColorMap ifNil: [
		| screen |
		screen := monitor workbenchScreenPointer.
		screen ifNil: [ ^ nil ].
		wbColorMap := monitor readMemoryAt: screen + 48 size: 4 ]
]

{ #category : #'reading' }
GT4AmigaChipRegisters >> rgb4At: anIndex [
	"Palette entry as the OS knows it, via graphics GetRGB4 (LVO -582,
	 colormap in a0, entry in d0). Answers nil when the link is down or
	 the entry does not exist (GetRGB4 answers -1)."
	| cmap v |
	cmap := self workbenchColorMap.
	cmap ifNil: [ ^ nil ].
	v := monitor callLibrary: 3 lvo: -582 a0: cmap a1: 0 d0: anIndex d1: 0 d2: 0 d3: 0.
	(v isNil or: [ v = 16rFFFFFFFF ]) ifTrue: [ ^ nil ].
	^ v
]

{ #category : #'reading' }
GT4AmigaChipRegisters >> gfxBase [
	"graphics.library base, discovered once per session: AllocMem a scratch
	 buffer, block-write the library name into it, OldOpenLibrary (exec LVO
	 -408), CloseLibrary right away (the monitor holds graphics.library open
	 since startup, so the base cannot expunge), FreeMem the buffer."
	| buf base |
	gfxBase ifNotNil: [ ^ gfxBase ].
	buf := monitor callLibrary: 0 lvo: -198 a0: 0 a1: 0 d0: 24 d1: 16r10002 d2: 0 d3: 0.
	(buf isNil or: [ buf = 0 ]) ifTrue: [ ^ nil ].
	monitor writeMemoryAt: buf bytes: 'graphics.library' asByteArray , #[0].
	base := monitor callLibrary: 0 lvo: -408 a0: 0 a1: buf d0: 0 d1: 0 d2: 0 d3: 0.
	(base isNil or: [ base = 0 ])
		ifFalse: [ monitor callLibrary: 0 lvo: -414 a0: 0 a1: base d0: 0 d1: 0 d2: 0 d3: 0 ].
	monitor callLibrary: 0 lvo: -210 a0: 0 a1: buf d0: 24 d1: 0 d2: 0 d3: 0.
	(base isNil or: [ base = 0 ]) ifTrue: [ ^ nil ].
	^ gfxBase := base
]

{ #category : #'reading' }
GT4AmigaChipRegisters >> copperListBytes [
	"A snapshot of the copper list the machine is displaying right now
	 (GfxBase->LOFlist, offset 50 per graphics/gfxbase.i), fetched with one
	 block read and cached for a second, so a full refresh scans one
	 snapshot instead of fetching the list once per derived register.
	 Serial I/O - background only."
	| gfx lof |
	(copperSnapshot notNil
		and: [ copperSnapshotAt notNil
		and: [ DateAndTime now - copperSnapshotAt < 1 second ] ])
			ifTrue: [ ^ copperSnapshot ].
	gfx := self gfxBase.
	gfx ifNil: [ ^ nil ].
	lof := monitor readMemoryAt: gfx + 50 size: 4.
	(lof isNil or: [ lof = 0 ]) ifTrue: [ ^ nil ].
	^ (monitor readMemoryAt: lof length: 1024)
		ifNotNil: [ :bytes |
			copperSnapshotAt := DateAndTime now.
			copperSnapshot := bytes ]
]

{ #category : #'reading' }
GT4AmigaChipRegisters >> copperMovesTo: anOffset [
	"Every value the live copper list MOVEs into the custom register at
	 anOffset, in beam order. A copper MOVE is a word pair with bit 0 of
	 the first word clear (the register offset in bits 8-1); scanning
	 stops at the end-of-list WAIT $FFFF,$FFFE."
	| bytes moves i w1 w2 |
	moves := OrderedCollection new.
	bytes := self copperListBytes.
	bytes ifNil: [ ^ moves ].
	i := 1.
	[ i + 3 <= bytes size ] whileTrue: [
		w1 := ((bytes at: i) bitShift: 8) + (bytes at: i + 1).
		w2 := ((bytes at: i + 2) bitShift: 8) + (bytes at: i + 3).
		(w1 = 16rFFFF and: [ w2 = 16rFFFE ]) ifTrue: [ ^ moves ].
		((w1 bitAnd: 1) = 0 and: [ (w1 bitAnd: 16r1FE) = anOffset ])
			ifTrue: [ moves add: w2 ].
		i := i + 4 ].
	^ moves
]

{ #category : #'reading' }
GT4AmigaChipRegisters >> copperMoveTo: anOffset [
	"The first value the live copper list MOVEs into the register at
	 anOffset, or nil when the list does not touch it. Right for the
	 registers Workbench writes once per frame (DDF/DIW/modulos) - NOT
	 for BPLCON0, which the list also writes with zero planes during the
	 blanking preamble and postamble; see installCopperDerivations."
	^ (self copperMovesTo: anOffset) ifEmpty: [ nil ] ifNotEmpty: [ :moves | moves first ]
]

{ #category : #'private - building' }
GT4AmigaChipRegisters >> installCopperDerivations [
	"The write-only display registers are rewritten by Workbench's copper
	 list every frame, so the MOVEs to them in that list ARE the machine's
	 effective display state. BPLCON0 is special: the list also writes it
	 with zero planes during the blanking preamble and postamble, so the
	 display's working value is the move with the most planes (with several
	 dragged screens: the deepest one)."
	#('DIWSTRT' 'DIWSTOP' 'DDFSTRT' 'DDFSTOP'
	  'BPLCON1' 'BPLCON2' 'BPL1MOD' 'BPL2MOD') do: [ :aName |
		| off |
		off := (registers at: aName) offset.
		(registers at: aName) derivation: [ :cat | cat copperMoveTo: off ] ].
	(registers at: 'BPLCON0') derivation: [ :cat |
		(cat copperMovesTo: 16r100)
			ifEmpty: [ nil ]
			ifNotEmpty: [ :moves | moves detectMax: [ :v | v bitAnd: 16r7000 ] ] ]
]

{ #category : #'private - building' }
GT4AmigaChipRegisters >> addRegister: aName offset: anOffset readOffset: aReadOffsetOrNil mode: aMode description: aString fields: anArrayOfSpecs [
	| reg |
	reg := GT4AmigaChipRegister new
		catalog: self;
		name: aName;
		offset: anOffset;
		readOffset: aReadOffsetOrNil;
		mode: aMode;
		description: aString;
		fields: (anArrayOfSpecs collect: [ :spec |
			GT4AmigaBitField new
				name: spec first;
				msb: spec second;
				lsb: spec third;
				description: spec fourth;
				yourself ]);
		yourself.
	registers at: aName put: reg.
	^ reg
]

{ #category : #'private - building' }
GT4AmigaChipRegisters >> dmaFields [
	"hardware/dmabits.i"
	^ {
		{ 'SETCLR'. 15. 15. 'On writes: 1 = set the masked bits, 0 = clear them' }.
		{ 'BBUSY'. 14. 14. 'Blitter busy (read only)' }.
		{ 'BZERO'. 13. 13. 'Last blitter result was all zeroes (read only)' }.
		{ 'BLTPRI'. 10. 10. 'Blitter priority over CPU ("blitter hog")' }.
		{ 'DMAEN'. 9. 9. 'Master DMA enable - gates all channels below' }.
		{ 'BPLEN'. 8. 8. 'Bitplane (raster) DMA' }.
		{ 'COPEN'. 7. 7. 'Copper DMA' }.
		{ 'BLTEN'. 6. 6. 'Blitter DMA' }.
		{ 'SPREN'. 5. 5. 'Sprite DMA' }.
		{ 'DSKEN'. 4. 4. 'Disk DMA' }.
		{ 'AUD3EN'. 3. 3. 'Audio channel 3 DMA' }.
		{ 'AUD2EN'. 2. 2. 'Audio channel 2 DMA' }.
		{ 'AUD1EN'. 1. 1. 'Audio channel 1 DMA' }.
		{ 'AUD0EN'. 0. 0. 'Audio channel 0 DMA' } }
]

{ #category : #'private - building' }
GT4AmigaChipRegisters >> intFields [
	"hardware/intbits.i (INTEN, bit 14, is meaningful in INTENA only)"
	^ {
		{ 'SETCLR'. 15. 15. 'On writes: 1 = set the masked bits, 0 = clear them' }.
		{ 'INTEN'. 14. 14. 'Master interrupt enable (INTENA only)' }.
		{ 'EXTER'. 13. 13. 'External interrupt (CIA-B, level 6)' }.
		{ 'DSKSYNC'. 12. 12. 'Disk re-synchronized' }.
		{ 'RBF'. 11. 11. 'Serial receive buffer full' }.
		{ 'AUD3'. 10. 10. 'Audio channel 3 block finished' }.
		{ 'AUD2'. 9. 9. 'Audio channel 2 block finished' }.
		{ 'AUD1'. 8. 8. 'Audio channel 1 block finished' }.
		{ 'AUD0'. 7. 7. 'Audio channel 0 block finished' }.
		{ 'BLIT'. 6. 6. 'Blitter finished' }.
		{ 'VERTB'. 5. 5. 'Start of vertical blank' }.
		{ 'COPER'. 4. 4. 'Copper interrupt' }.
		{ 'PORTS'. 3. 3. 'I/O ports and timers (CIA-A, level 2)' }.
		{ 'SOFT'. 2. 2. 'Software interrupt request' }.
		{ 'DSKBLK'. 1. 1. 'Disk block done' }.
		{ 'TBE'. 0. 0. 'Serial transmit buffer empty' } }
]

{ #category : #'private - building' }
GT4AmigaChipRegisters >> adkFields [
	"hardware/adkbits.i"
	^ {
		{ 'SETCLR'. 15. 15. 'On writes: 1 = set the masked bits, 0 = clear them' }.
		{ 'PRECOMP'. 14. 13. 'Disk write precompensation (00=none 01=140ns 10=280ns 11=560ns)' }.
		{ 'MFMPREC'. 12. 12. 'MFM-style precompensation (else GCR)' }.
		{ 'UARTBRK'. 11. 11. 'Force UART output to zero (break)' }.
		{ 'WORDSYNC'. 10. 10. 'Enable DSKSYNC register matching' }.
		{ 'MSBSYNC'. 9. 9. 'Sync on MSB for reading (GCR)' }.
		{ 'FAST'. 8. 8. 'Disk bit cell: 1 = 2 microseconds (MFM)' }.
		{ 'USE3PN'. 7. 7. 'Audio ch 3 modulates period of nothing' }.
		{ 'USE2P3'. 6. 6. 'Audio ch 2 modulates period of ch 3' }.
		{ 'USE1P2'. 5. 5. 'Audio ch 1 modulates period of ch 2' }.
		{ 'USE0P1'. 4. 4. 'Audio ch 0 modulates period of ch 1' }.
		{ 'USE3VN'. 3. 3. 'Audio ch 3 modulates volume of nothing' }.
		{ 'USE2V3'. 2. 2. 'Audio ch 2 modulates volume of ch 3' }.
		{ 'USE1V2'. 1. 1. 'Audio ch 1 modulates volume of ch 2' }.
		{ 'USE0V1'. 0. 0. 'Audio ch 0 modulates volume of ch 1' } }
]

{ #category : #'private - building' }
GT4AmigaChipRegisters >> buildRegisters [
	"Addresses verified against hardware/custom.i."
	self addRegister: 'DMACONR' offset: 16r002 readOffset: nil mode: #read
		description: 'DMA control and blitter status, read side' fields: self dmaFields.
	self addRegister: 'VPOSR' offset: 16r004 readOffset: nil mode: #read
		description: 'Beam position: frame bits' fields: {
			{ 'LOF'. 15. 15. 'Long frame (interlace: 1 = long field)' }.
			{ 'V8'. 0. 0. 'Vertical beam position bit 8' } }.
	self addRegister: 'VHPOSR' offset: 16r006 readOffset: nil mode: #read
		description: 'Beam position: vertical low bits and horizontal' fields: {
			{ 'VPOS'. 15. 8. 'Vertical beam position V7-V0' }.
			{ 'HPOS'. 7. 0. 'Horizontal beam position H8-H1 (280 ns steps)' } }.
	self addRegister: 'ADKCONR' offset: 16r010 readOffset: nil mode: #read
		description: 'Audio/disk control, read side' fields: self adkFields.
	self addRegister: 'INTENAR' offset: 16r01C readOffset: nil mode: #read
		description: 'Interrupt enable bits, read side' fields: self intFields.
	self addRegister: 'INTREQR' offset: 16r01E readOffset: nil mode: #read
		description: 'Interrupt request bits (pending), read side' fields: self intFields.

	self addRegister: 'COP1LCH' offset: 16r080 readOffset: nil mode: #write
		description: 'Copper list 1 pointer, high word' fields: #().
	self addRegister: 'COP1LCL' offset: 16r082 readOffset: nil mode: #write
		description: 'Copper list 1 pointer, low word' fields: #().
	self addRegister: 'COP2LCH' offset: 16r084 readOffset: nil mode: #write
		description: 'Copper list 2 pointer, high word' fields: #().
	self addRegister: 'COP2LCL' offset: 16r086 readOffset: nil mode: #write
		description: 'Copper list 2 pointer, low word' fields: #().
	self addRegister: 'COPJMP1' offset: 16r088 readOffset: nil mode: #strobe
		description: 'Restart copper at COP1LC (writing is the operation)' fields: #().
	self addRegister: 'COPJMP2' offset: 16r08A readOffset: nil mode: #strobe
		description: 'Restart copper at COP2LC (writing is the operation)' fields: #().

	self addRegister: 'DIWSTRT' offset: 16r08E readOffset: nil mode: #write
		description: 'Display window start (upper left corner)' fields: {
			{ 'VSTART'. 15. 8. 'Vertical start position' }.
			{ 'HSTART'. 7. 0. 'Horizontal start position' } }.
	self addRegister: 'DIWSTOP' offset: 16r090 readOffset: nil mode: #write
		description: 'Display window stop (lower right corner)' fields: {
			{ 'VSTOP'. 15. 8. 'Vertical stop position' }.
			{ 'HSTOP'. 7. 0. 'Horizontal stop position' } }.
	self addRegister: 'DDFSTRT' offset: 16r092 readOffset: nil mode: #write
		description: 'Display data fetch start (horizontal)' fields: #().
	self addRegister: 'DDFSTOP' offset: 16r094 readOffset: nil mode: #write
		description: 'Display data fetch stop (horizontal)' fields: #().

	self addRegister: 'DMACON' offset: 16r096 readOffset: 16r002 mode: #setClear
		description: 'DMA control, write side (SET/CLR protocol; readable through DMACONR)' fields: self dmaFields.
	self addRegister: 'INTENA' offset: 16r09A readOffset: 16r01C mode: #setClear
		description: 'Interrupt enable, write side (SET/CLR; readable through INTENAR)' fields: self intFields.
	self addRegister: 'INTREQ' offset: 16r09C readOffset: 16r01E mode: #setClear
		description: 'Interrupt request, write side (SET/CLR; readable through INTREQR)' fields: self intFields.
	self addRegister: 'ADKCON' offset: 16r09E readOffset: 16r010 mode: #setClear
		description: 'Audio/disk control, write side (SET/CLR; readable through ADKCONR)' fields: self adkFields.

	self addRegister: 'BPLCON0' offset: 16r100 readOffset: nil mode: #write
		description: 'Bitplane control: resolution, depth, modes' fields: {
			{ 'HIRES'. 15. 15. 'High resolution (640 pixels)' }.
			{ 'BPU'. 14. 12. 'Number of bitplanes in use (0-6)' }.
			{ 'HAM'. 11. 11. 'Hold-and-modify mode' }.
			{ 'DBLPF'. 10. 10. 'Dual playfield mode' }.
			{ 'COLOR'. 9. 9. 'Composite video color burst' }.
			{ 'GAUD'. 8. 8. 'Genlock audio' }.
			{ 'LPEN'. 3. 3. 'Light pen enable' }.
			{ 'LACE'. 2. 2. 'Interlace' }.
			{ 'ERSY'. 1. 1. 'External resync (genlock)' } }.
	self addRegister: 'BPLCON1' offset: 16r102 readOffset: nil mode: #write
		description: 'Bitplane control: horizontal fine scroll' fields: {
			{ 'PF2H'. 7. 4. 'Playfield 2 horizontal scroll (pixels)' }.
			{ 'PF1H'. 3. 0. 'Playfield 1 horizontal scroll (pixels)' } }.
	self addRegister: 'BPLCON2' offset: 16r104 readOffset: nil mode: #write
		description: 'Bitplane control: playfield priority' fields: {
			{ 'PF2PRI'. 6. 6. 'Playfield 2 has priority over playfield 1' }.
			{ 'PF2P'. 5. 3. 'Playfield 2 priority vs sprites' }.
			{ 'PF1P'. 2. 0. 'Playfield 1 priority vs sprites' } }.
	self addRegister: 'BPL1MOD' offset: 16r108 readOffset: nil mode: #write
		description: 'Modulo for odd bitplanes (bytes added after each row)' fields: #().
	self addRegister: 'BPL2MOD' offset: 16r10A readOffset: nil mode: #write
		description: 'Modulo for even bitplanes (bytes added after each row)' fields: #().

	self buildColorRegisters.
	self installCopperDerivations
]

{ #category : #'private - building' }
GT4AmigaChipRegisters >> buildColorRegisters [
	"COLOR00-COLOR31 at $180... - write-only latches that the Workbench
	 copper list rewrites every frame, so their truthful value comes from
	 the OS ColorMap (GetRGB4), not from a hardware read."
	0 to: 31 do: [ :i |
		| reg |
		reg := self
			addRegister: 'COLOR' , (i printPaddedWith: $0 to: 2 base: 10)
			offset: 16r180 + (i * 2)
			readOffset: nil
			mode: #write
			description: 'Palette entry ' , i printString , ' (RGB, 4 bits per gun)'
			fields: {
				{ 'R'. 11. 8. 'Red intensity' }.
				{ 'G'. 7. 4. 'Green intensity' }.
				{ 'B'. 3. 0. 'Blue intensity' } }.
		reg derivation: [ :cat | cat rgb4At: i ] ]
]

{ #category : #'gt-extensions' }
GT4AmigaChipRegisters >> gtRegistersFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Registers';
		priority: 5;
		items: [ registers values ];
		column: 'Name' text: [ :r | r name ] width: 80;
		column: 'Address' text: [ :r | r addressString ] width: 80;
		column: 'Mode' text: [ :r | r mode ] width: 70;
		column: 'Value' text: [ :r | r valueString ] width: 60;
		column: 'Description' text: [ :r | r description ];
		updateWhen: GT4AmigaRegistersRefreshed in: announcer
]

{ #category : #'gt-extensions' }
GT4AmigaChipRegisters >> gtActionRefreshFor: anAction [
	<gtAction>
	^ anAction button
		label: 'Refresh';
		tooltip: 'Re-read every readable register from the Amiga (in the background)';
		action: [ [ self refresh ] fork ]
]

{ #category : #'printing' }
GT4AmigaChipRegisters >> printOn: aStream [
	aStream
		nextPutAll: 'Amiga custom chip registers (';
		print: registers size;
		nextPutAll: ' modeled)'
]
