"
I am the whole machine: the Amiga 500 as one live object. I decompose it three ways, each a drill-down into the same live GT4AmigaChipRegisters catalog:

  chips       PHYSICAL - 68000, Agnus, Denise, Paula, the two CIAs; each with the custom
              registers the AHRM Appendix B chip column assigns to it
  subsystems  FUNCTIONAL - DMA, interrupts, Copper, playfield, color, beam, audio/disk;
              the registers you program together regardless of which silicon holds them
  regions     the ADDRESS MAP - Chip RAM, CIAs, Slow RAM, custom register file, Kickstart
              ROM; plain-memory regions offer a windowed live hex dump

I also keep the memory gauges: free chip/fast memory and the largest contiguous chip block via exec AvailMem (LVO -216, requirement flags in d1: MEMF_CHIP=2, MEMF_FAST=4, MEMF_LARGEST=$20000 - constants from exec/memory.i), and the RAM bounds the OS found at boot from ExecBase: MaxLocMem (ExecBase+62, top of chip RAM) and MaxExtMem (ExecBase+78, top of the $C00000 slow RAM - which 1.3 exec lists as MEMF_FAST, there being nothing faster on an A500).

Usage:
	machine := GT4AmigaMachine default.
	[ machine refresh ] fork.               (re-read the gauges - NEVER on the UI thread)
	machine chipNamed: 'Agnus'.
	(machine regionNamed: 'Chip RAM') isDumpable.

refresh announces GT4AmigaMachineRefreshed through my announcer, so the memory view updates itself after a background refresh. I am the model layer only: I hold no Bloc code (the block diagram element lives in GT4Amiga-Hardware-UI).
"
Class {
	#name : #GT4AmigaMachine,
	#superclass : #Object,
	#instVars : [
		'catalog',
		'announcer',
		'chips',
		'subsystems',
		'regions',
		'execBase',
		'maxLocMem',
		'maxExtMem',
		'chipFree',
		'fastFree',
		'largestChip'
	],
	#classVars : [
		'Default'
	],
	#category : #'GT4Amiga-Hardware'
}

{ #category : #'accessing' }
GT4AmigaMachine class >> default [
	^ Default ifNil: [ Default := self new ]
]

{ #category : #'accessing' }
GT4AmigaMachine class >> default: aMachine [
	Default := aMachine
]

{ #category : #'initialization' }
GT4AmigaMachine >> initialize [
	catalog := GT4AmigaChipRegisters default.
	announcer := Announcer new.
	self buildChips.
	self buildSubsystems.
	self buildRegions
]

{ #category : #'accessing' }
GT4AmigaMachine >> catalog [
	^ catalog
]

{ #category : #'accessing' }
GT4AmigaMachine >> catalog: aCatalog [
	catalog := aCatalog
]

{ #category : #'accessing' }
GT4AmigaMachine >> announcer [
	^ announcer
]

{ #category : #'accessing' }
GT4AmigaMachine >> chips [
	^ chips
]

{ #category : #'accessing' }
GT4AmigaMachine >> subsystems [
	^ subsystems
]

{ #category : #'accessing' }
GT4AmigaMachine >> regions [
	^ regions
]

{ #category : #'accessing' }
GT4AmigaMachine >> chipNamed: aName [
	^ chips detect: [ :each | each name = aName ]
]

{ #category : #'accessing' }
GT4AmigaMachine >> subsystemNamed: aName [
	^ subsystems detect: [ :each | each name = aName ]
]

{ #category : #'accessing' }
GT4AmigaMachine >> regionNamed: aName [
	^ regions detect: [ :each | each name = aName ]
]

{ #category : #'accessing' }
GT4AmigaMachine >> execBase [
	^ execBase
]

{ #category : #'accessing' }
GT4AmigaMachine >> chipFree [
	^ chipFree
]

{ #category : #'accessing' }
GT4AmigaMachine >> fastFree [
	^ fastFree
]

{ #category : #'accessing' }
GT4AmigaMachine >> largestChip [
	^ largestChip
]

{ #category : #'accessing' }
GT4AmigaMachine >> maxLocMem [
	^ maxLocMem
]

{ #category : #'accessing' }
GT4AmigaMachine >> maxExtMem [
	^ maxExtMem
]

{ #category : #'reading' }
GT4AmigaMachine >> availMem: requirementFlags [
	"exec AvailMem (LVO -216). The requirement flags travel in d1
	 (NOT d0 - Function.offs: 'AvailMem(requirements)(d1)')."
	^ catalog monitor
		callLibrary: 0 lvo: -216
		a0: 0 a1: 0
		d0: 0 d1: requirementFlags d2: 0 d3: 0
]

{ #category : #'reading' }
GT4AmigaMachine >> refresh [
	"Re-read the memory gauges from the machine and announce, so
	 subscribed views re-render. Serial I/O: call from a background
	 process, never the UI thread. Keeps previous values on nil (link
	 down), same policy as the register cache."
	| monitor |
	monitor := catalog monitor.
	(monitor readMemoryAt: 4 size: 4) ifNotNil: [ :v | execBase := v ].
	execBase ifNotNil: [
		(monitor readMemoryAt: execBase + 62 size: 4) ifNotNil: [ :v | maxLocMem := v ].
		(monitor readMemoryAt: execBase + 78 size: 4) ifNotNil: [ :v | maxExtMem := v ] ].
	(self availMem: 2) ifNotNil: [ :v | chipFree := v ].              "MEMF_CHIP"
	(self availMem: 4) ifNotNil: [ :v | fastFree := v ].              "MEMF_FAST"
	(self availMem: 2 + 16r20000) ifNotNil: [ :v | largestChip := v ]."MEMF_CHIP|MEMF_LARGEST"
	announcer announce: GT4AmigaMachineRefreshed new
]

{ #category : #'private - building' }
GT4AmigaMachine >> buildChips [
	chips := OrderedCollection new.
	chips add: (GT4AmigaChip
		machine: self name: '68000' nickname: 'MC68000 CPU'
		description: 'The processor. Owns no custom registers: it reaches them like any other address, sharing the chip bus with the DMA channels on alternate cycles.'
		registerNames: #()).
	chips add: (GT4AmigaChip
		machine: self name: 'Agnus' nickname: '8371 Agnus'
		description: 'Address generator: arbitrates the chip bus, runs all 25 DMA channels, the Copper, the blitter and the beam counters. Everything that MOVES data is Agnus.'
		registerNames: #('DMACONR' 'DMACON' 'VPOSR' 'VHPOSR'
			'COP1LCH' 'COP1LCL' 'COP2LCH' 'COP2LCL' 'COPJMP1' 'COPJMP2'
			'DIWSTRT' 'DIWSTOP' 'DDFSTRT' 'DDFSTOP'
			'BPL1MOD' 'BPL2MOD' 'BPLCON0')).
	chips add: (GT4AmigaChip
		machine: self name: 'Denise' nickname: '8362 Denise'
		description: 'Video: serializes bitplane data into pixels, applies the palette, priorities and sprites. Everything you SEE leaves the machine through Denise.'
		registerNames: (#('DMACON' 'BPLCON0' 'BPLCON1' 'BPLCON2') ,
			((0 to: 31) collect: [ :i | 'COLOR' , (i printPaddedWith: $0 to: 2 base: 10) ]))).
	chips add: (GT4AmigaChip
		machine: self name: 'Paula' nickname: '8364 Paula'
		description: 'Interrupts, audio, floppy and serial port. The monitor link itself lives here: the serial interrupts (RBF/TBE) are Paula bits - which is why they are locked in the control panel.'
		registerNames: #('DMACONR' 'DMACON' 'INTENAR' 'INTENA' 'INTREQR' 'INTREQ' 'ADKCONR' 'ADKCON')).
	chips add: (GT4AmigaChip
		machine: self name: 'CIA-A' nickname: '8520 CIA-A ($BFE001)'
		description: 'Complex Interface Adapter A: keyboard, mouse buttons, floppy status, the power LED (and audio filter) bit. Its registers live at $BFE001, odd bytes.'
		registerNames: #()).
	chips add: (GT4AmigaChip
		machine: self name: 'CIA-B' nickname: '8520 CIA-B ($BFD000)'
		description: 'Complex Interface Adapter B: serial/parallel control lines, floppy motor and step control, the horizontal-sync event counter. Its registers live at $BFD000, even bytes.'
		registerNames: #())
]

{ #category : #'private - building' }
GT4AmigaMachine >> buildSubsystems [
	subsystems := OrderedCollection new.
	subsystems add: (GT4AmigaSubsystem
		machine: self name: 'DMA'
		description: 'Central control of the 25 DMA channels: one enable bit per channel plus the DMAEN master switch.'
		registerNames: #('DMACONR' 'DMACON')).
	subsystems add: (GT4AmigaSubsystem
		machine: self name: 'Interrupts'
		description: '14 interrupt sources funneled into the 68000''s levels 1-6: enable mask, request latch, and the INTEN master.'
		registerNames: #('INTENAR' 'INTENA' 'INTREQR' 'INTREQ')).
	subsystems add: (GT4AmigaSubsystem
		machine: self name: 'Copper'
		description: 'The video coprocessor: two program location registers and their restart strobes. Its program rewrites the chip registers in sync with the beam, every frame.'
		registerNames: #('COP1LCH' 'COP1LCL' 'COP2LCH' 'COP2LCL' 'COPJMP1' 'COPJMP2')).
	subsystems add: (GT4AmigaSubsystem
		machine: self name: 'Playfield'
		description: 'The bitplane display: control (depth, resolution), fetch window, display window and modulos - Agnus fetches, Denise draws.'
		registerNames: #('BPLCON0' 'BPLCON1' 'BPLCON2' 'BPL1MOD' 'BPL2MOD'
			'DIWSTRT' 'DIWSTOP' 'DDFSTRT' 'DDFSTOP')).
	subsystems add: (GT4AmigaSubsystem
		machine: self name: 'Color'
		description: 'The 32-entry palette, 4 bits per gun. On the running Workbench the Copper reloads it every frame, so the OS ColorMap is the truth.'
		registerNames: ((0 to: 31) collect: [ :i | 'COLOR' , (i printPaddedWith: $0 to: 2 base: 10) ])).
	subsystems add: (GT4AmigaSubsystem
		machine: self name: 'Beam'
		description: 'Where the video beam is right now - the position counters Agnus keeps while it paints the frame.'
		registerNames: #('VPOSR' 'VHPOSR')).
	subsystems add: (GT4AmigaSubsystem
		machine: self name: 'Audio and disk'
		description: 'Paula''s audio modulation and disk/UART control bits.'
		registerNames: #('ADKCONR' 'ADKCON'))
]

{ #category : #'private - building' }
GT4AmigaMachine >> buildRegions [
	"The A500 address map as configured in FS-UAE (512 KB chip + 512 KB
	 slow, Kickstart 1.3). The RAM sizes here are the boot-time defaults;
	 refresh reads the real bounds (MaxLocMem/MaxExtMem) from ExecBase."
	regions := OrderedCollection new.
	regions add: (GT4AmigaMemoryRegion
		machine: self name: 'Chip RAM' start: 16r000000 size: 16r80000 kind: #chipRam
		description: 'Memory both the 68000 and the custom chips can reach: bitplanes, Copper lists, sprites, audio samples MUST live here. Location 4 holds the ExecBase pointer.').
	regions add: (GT4AmigaMemoryRegion
		machine: self name: 'CIA-B' start: 16rBFD000 size: 16r1000 kind: #cia
		description: '8520 CIA-B registers, even bytes. NOT dumpable: reading a CIA interrupt control register clears it.').
	regions add: (GT4AmigaMemoryRegion
		machine: self name: 'CIA-A' start: 16rBFE001 size: 16r1000 kind: #cia
		description: '8520 CIA-A registers, odd bytes. NOT dumpable: reading a CIA interrupt control register clears it.').
	regions add: (GT4AmigaMemoryRegion
		machine: self name: 'Slow RAM' start: 16rC00000 size: 16r80000 kind: #slowRam
		description: 'The A501 expansion: the CPU reaches it through Agnus timing (as slow as chip RAM) but the DMA channels cannot use it. 1.3 exec lists it as MEMF_FAST - ExecBase itself lives here.').
	regions add: (GT4AmigaMemoryRegion
		machine: self name: 'Custom chips' start: 16rDFF000 size: 16r1000 kind: #custom
		description: 'The custom chip register file - the address space this whole book is about. NOT dumpable: registers demand word access and many are write-only.').
	regions add: (GT4AmigaMemoryRegion
		machine: self name: 'Kickstart ROM' start: 16rFC0000 size: 16r40000 kind: #rom
		description: '256 KB of Kickstart 1.3: exec, dos, intuition, graphics. Dumpable (it starts with the magic word $1111 and a JMP to the reset code - dump it and see).')
]

{ #category : #'gt-extensions' }
GT4AmigaMachine >> gtChipsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Chips';
		priority: 4;
		items: [ chips ];
		column: 'Chip' text: [ :c | c nickname ] width: 170;
		column: 'Registers' text: [ :c | c registerNames size printString ] width: 70;
		column: 'Description' text: [ :c | c description ]
]

{ #category : #'gt-extensions' }
GT4AmigaMachine >> gtSubsystemsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Subsystems';
		priority: 5;
		items: [ subsystems ];
		column: 'Subsystem' text: [ :s | s name ] width: 120;
		column: 'Registers' text: [ :s | s registerNames size printString ] width: 70;
		column: 'Chips' text: [ :s | (s chips collect: [ :c | c name ]) asCommaString ] width: 130;
		column: 'Description' text: [ :s | s description ]
]

{ #category : #'gt-extensions' }
GT4AmigaMachine >> gtMemoryMapFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Memory map';
		priority: 6;
		items: [ regions ];
		column: 'Region' text: [ :r | r name ] width: 110;
		column: 'Range' text: [ :r | r rangeString ] width: 140;
		column: 'Size' text: [ :r | r sizeString ] width: 70;
		column: 'Kind' text: [ :r | r kind ] width: 70;
		column: 'Description' text: [ :r | r description ]
]

{ #category : #'gt-extensions' }
GT4AmigaMachine >> gtMemoryFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Memory';
		priority: 7;
		items: [ self memoryGaugeRows ];
		column: 'Gauge' text: [ :row | row first ] width: 220;
		column: 'Value' text: [ :row | row second ] width: 110;
		column: 'Source' text: [ :row | row third ];
		updateWhen: GT4AmigaMachineRefreshed in: announcer
]

{ #category : #'gt-extensions' }
GT4AmigaMachine >> memoryGaugeRows [
	| fmt hex |
	fmt := [ :v | v
		ifNil: [ '?' ]
		ifNotNil: [ :n | n printString , ' bytes (' , (n // 1024) printString , ' KB)' ] ].
	hex := [ :v | v
		ifNil: [ '?' ]
		ifNotNil: [ :n | '$' , (n printPaddedWith: $0 to: 6 base: 16) ] ].
	^ {
		{ 'ExecBase'. hex value: execBase. 'pointer at location 4' }.
		{ 'Top of chip RAM (MaxLocMem)'. hex value: maxLocMem. 'ExecBase+62' }.
		{ 'Top of slow RAM (MaxExtMem)'. hex value: maxExtMem. 'ExecBase+78' }.
		{ 'Free chip memory'. fmt value: chipFree. 'AvailMem(MEMF_CHIP)' }.
		{ 'Free fast memory'. fmt value: fastFree. 'AvailMem(MEMF_FAST) - the $C00000 slow RAM on this A500' }.
		{ 'Largest free chip block'. fmt value: largestChip. 'AvailMem(MEMF_CHIP|MEMF_LARGEST)' } }
]

{ #category : #'gt-extensions' }
GT4AmigaMachine >> gtActionRefreshFor: anAction [
	<gtAction>
	^ anAction button
		label: 'Refresh';
		tooltip: 'Re-read the memory gauges from the Amiga (in the background)';
		action: [ [ self refresh ] fork ]
]

{ #category : #'printing' }
GT4AmigaMachine >> printOn: aStream [
	aStream
		nextPutAll: 'Amiga 500 (';
		print: chips size;
		nextPutAll: ' chips, ';
		print: subsystems size;
		nextPutAll: ' subsystems, ';
		print: regions size;
		nextPutAll: ' memory regions)'
]
