"
I am one region of the Amiga address map: Chip RAM, the CIAs, Slow RAM, the custom chip register file, the Kickstart ROM. My kind states what the region IS and whether it is safe to dump:

  #chipRam #slowRam #rom   plain memory - dumpable byte by byte
  #cia #custom             REGISTERS behind addresses - NOT dumpable, because reading
                           a register can have side effects (reading a CIA interrupt
                           control register CLEARS it; custom registers demand word
                           access and many are write-only, reads answer garbage)

Dumpable regions offer a windowed hex dump: dump is cached (a window of at most 4096 bytes fetched by the block-read opcode), views render only the cache, and readWindow / readWindowAt:length: do the serial I/O - call them from a background process, never the UI thread. After a fetch I announce GT4AmigaMachineRefreshed through the machine announcer so the dump view repaints itself.
"
Class {
	#name : #GT4AmigaMemoryRegion,
	#superclass : #Object,
	#instVars : [
		'machine',
		'name',
		'start',
		'size',
		'kind',
		'description',
		'window',
		'windowStart'
	],
	#category : #'GT4Amiga-Hardware'
}

{ #category : #'instance creation' }
GT4AmigaMemoryRegion class >> machine: aMachine name: aName start: aStart size: aSize kind: aKind description: aString [
	^ self new
		setMachine: aMachine
		name: aName
		start: aStart
		size: aSize
		kind: aKind
		description: aString
]

{ #category : #'initialization' }
GT4AmigaMemoryRegion >> setMachine: aMachine name: aName start: aStart size: aSize kind: aKind description: aString [
	machine := aMachine.
	name := aName.
	start := aStart.
	size := aSize.
	kind := aKind.
	description := aString
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> name [
	^ name
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> start [
	^ start
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> size [
	^ size
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> end [
	^ start + size - 1
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> kind [
	^ kind
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> description [
	^ description
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> rangeString [
	^ '$' , (start printPaddedWith: $0 to: 6 base: 16)
		, '-$' , (self end printPaddedWith: $0 to: 6 base: 16)
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> sizeString [
	size >= 1024 ifTrue: [ ^ (size // 1024) printString , ' KB' ].
	^ size printString , ' bytes'
]

{ #category : #'testing' }
GT4AmigaMemoryRegion >> isDumpable [
	^ #(chipRam slowRam rom) includes: kind
]

{ #category : #'reading' }
GT4AmigaMemoryRegion >> readWindow [
	"Fetch the first 256 bytes of the region (serial I/O - background only)."
	^ self readWindowAt: start length: 256
]

{ #category : #'reading' }
GT4AmigaMemoryRegion >> readWindowAt: anAddress length: aLength [
	"Fetch aLength bytes (at most 4096) at anAddress into my window cache
	 and announce, so the dump view repaints. Serial I/O - call from a
	 background process, never the UI thread. Refused on register regions:
	 byte reads there have side effects."
	| bytes |
	self isDumpable ifFalse: [ ^ nil ].
	bytes := machine catalog monitor
		readMemoryAt: anAddress
		length: (aLength min: 4096).
	bytes ifNil: [ ^ nil ].
	windowStart := anAddress.
	window := bytes.
	machine announcer announce: GT4AmigaMachineRefreshed new.
	^ bytes
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> window [
	^ window
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> windowStart [
	^ windowStart
]

{ #category : #'accessing' }
GT4AmigaMemoryRegion >> windowRows [
	"The cached window as hex-dump rows: {address. hex bytes. ascii}."
	window ifNil: [ ^ #() ].
	^ (1 to: window size by: 16) collect: [ :i |
		| slice |
		slice := window copyFrom: i to: (i + 15 min: window size).
		{ '$' , (windowStart + i - 1 printPaddedWith: $0 to: 6 base: 16).
		  (slice
			inject: ''
			into: [ :acc :b | acc , (b printPaddedWith: $0 to: 2 base: 16) , ' ' ]) trimBoth.
		  (slice
			collect: [ :b | (b between: 32 and: 126) ifTrue: [ b asCharacter ] ifFalse: [ $. ] ]
			as: String) } ]
]

{ #category : #'gt-extensions' }
GT4AmigaMemoryRegion >> gtDumpFor: aView [
	<gtView>
	self isDumpable ifFalse: [ ^ aView empty ].
	^ aView columnedList
		title: 'Dump';
		priority: 5;
		items: [ self windowRows ];
		column: 'Address' text: [ :row | row first ] width: 90;
		column: 'Bytes' text: [ :row | row second ] width: 380;
		column: 'ASCII' text: [ :row | row third ];
		updateWhen: GT4AmigaMachineRefreshed in: machine announcer
]

{ #category : #'gt-extensions' }
GT4AmigaMemoryRegion >> gtActionReadWindowFor: anAction [
	<gtAction>
	self isDumpable ifFalse: [ ^ anAction noAction ].
	^ anAction button
		label: 'Read window';
		tooltip: 'Fetch the first 256 bytes of the region (in the background)';
		action: [ [ self readWindow ] fork ]
]

{ #category : #'gt-extensions' }
GT4AmigaMemoryRegion >> gtDetailsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Details';
		priority: 6;
		items: [ {
			{ 'Name'. name }.
			{ 'Range'. self rangeString }.
			{ 'Size'. self sizeString }.
			{ 'Kind'. kind printString }.
			{ 'Dumpable'. self isDumpable printString }.
			{ 'Description'. description } } ];
		column: 'Property' text: [ :pair | pair first ] width: 90;
		column: 'Value' text: [ :pair | pair second ]
]

{ #category : #'printing' }
GT4AmigaMemoryRegion >> printOn: aStream [
	aStream
		nextPutAll: name;
		nextPutAll: ' ';
		nextPutAll: self rangeString
]
