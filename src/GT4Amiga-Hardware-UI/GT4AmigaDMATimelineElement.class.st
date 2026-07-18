"
The AHRM's centerpiece figure (6-9, 'DMA Time Slot Allocation / Horizontal Line') as a LIVE element: one horizontal scan line of 227 color clocks ($00-$E2, one memory access cycle each), folded into two rows, every slot colored by the device that owns it - and parameterized by the machine's real state instead of being a printed diagram:

- the fixed allocations from figure 6-9: memory refresh at $01-$07, disk DMA at $09-$0D, the four audio channels at $0F-$15, the eight sprites (two words each) at $17-$35 - all on ODD slots, because the even slots are the 68000's memory-access half (figure 6-10);
- the bitplane fetch window from the LIVE DDFSTRT/DDFSTOP (read out of Workbench's own copper list), with the fetch order per 8-clock group from figures 6-11/6-12: lores '- 4 6 2 - 3 5 1' (planes 1-4 on odd slots; planes 5-6 STEAL the 68000's even slots), hires '4 2 3 1' on every slot - drawn only up to the live BPU plane count from BPLCON0, clamped to the hardware fetch stop at $D8, and stealing sprite slots when the window starts early;
- channels disabled in the live DMACON render pale: the slot is reserved but stands open to the Copper, the blitter and the 68000.

Hover a slot and the status line names it; click and the owning register (BPLCON0 for bitplane slots, DMACON for the rest) opens in the inspector. Toggle BPLEN in the control panel and watch 80 slots go pale.

Threading contract (project rule: no serial I/O on the UI thread): a background worker polls DMACON, BPLCON0, DDFSTRT and DDFSTOP every 2 seconds while I am in the scene graph (the three copper-derived reads share one cached copper-list snapshot) and announces GT4AmigaRegistersRefreshed on the catalog announcer; the handler repaints from the register CACHE via an enqueued Bloc task; the worker stops when I leave the scene graph.

Open me with: GT4AmigaDMATimelineElement onMachine: GT4AmigaMachine default - or inspect the machine and pick the DMA timeline view.
"
Class {
	#name : #GT4AmigaDMATimelineElement,
	#superclass : #BlElement,
	#instVars : [
		'machine',
		'dmacon',
		'bplcon0',
		'ddfstrt',
		'ddfstop',
		'cells',
		'owners',
		'summaryLabel',
		'statusLabel'
	],
	#category : #'GT4Amiga-Hardware-UI'
}

{ #category : #'instance creation' }
GT4AmigaDMATimelineElement class >> onMachine: aMachine [
	^ self new setMachine: aMachine
]

{ #category : #'instance creation' }
GT4AmigaDMATimelineElement >> setMachine: aMachine [
	machine := aMachine.
	dmacon := machine catalog at: 'DMACON'.
	bplcon0 := machine catalog at: 'BPLCON0'.
	ddfstrt := machine catalog at: 'DDFSTRT'.
	ddfstop := machine catalog at: 'DDFSTOP'.
	self size: 724 @ 214.
	self buildTimeline.
	self updateFromCache.
	self addEventHandlerOn: BlElementAddedToSceneGraphEvent do: [ :evt | self startObserving ].
	self addEventHandlerOn: BlElementRemovedFromSceneGraphEvent do: [ :evt | self stopObserving ]
]

{ #category : #'building' }
GT4AmigaDMATimelineElement >> buildTimeline [
	summaryLabel := BlTextElement new
		text: (GT4AmigaControlPanelElement text: '' size: 10 color: Color darkGray);
		relocate: 20 @ 6;
		yourself.
	self addChild: summaryLabel.
	cells := Array new: 227.
	0 to: 226 do: [ :clock | self buildCellFor: clock ].
	16r00 to: 16r70 by: 16r10 do: [ :c | self tickAt: c row: 0 ].
	16r80 to: 16rE0 by: 16r10 do: [ :c | self tickAt: c row: 1 ].
	self labelAt: 24 @ 63 text: 'refresh'.
	self labelAt: 70 @ 63 text: 'disk'.
	self labelAt: 112 @ 63 text: 'audio 0-3'.
	self labelAt: 216 @ 63 text: 'sprites 0-7 (2 words each)'.
	statusLabel := BlTextElement new
		text: (GT4AmigaControlPanelElement
			text: 'hover a slot to read its story' size: 10 color: Color gray);
		relocate: 20 @ 128;
		yourself.
	self addChild: statusLabel.
	self buildLegend
]

{ #category : #'building' }
GT4AmigaDMATimelineElement >> buildCellFor: aClock [
	| cell |
	cell := BlElement new
		size: 5 @ 22;
		relocate: (self cellPositionFor: aClock);
		background: (Color gray alpha: 0.12);
		yourself.
	cell addEventHandlerOn: BlMouseEnterEvent do: [ :evt |
		statusLabel text: (GT4AmigaControlPanelElement
			text: (self slotDescription: aClock) size: 10 color: Color darkGray) ].
	cell addEventHandlerOn: BlClickEvent do: [ :evt |
		evt consumed: true.
		cell phlow spawnObject: (((owners at: aClock + 1) isKindOf: Association)
			ifTrue: [ ((owners at: aClock + 1) key = #bitplane) ifTrue: [ bplcon0 ] ifFalse: [ dmacon ] ]
			ifFalse: [ dmacon ]) ].
	cells at: aClock + 1 put: cell.
	self addChild: cell
]

{ #category : #'building' }
GT4AmigaDMATimelineElement >> cellPositionFor: aClock [
	^ aClock < 114
		ifTrue: [ (20 + (aClock * 6)) @ 38 ]
		ifFalse: [ (20 + ((aClock - 114) * 6)) @ 96 ]
]

{ #category : #'building' }
GT4AmigaDMATimelineElement >> tickAt: aClock row: aRow [
	| x |
	x := aRow = 0
		ifTrue: [ 20 + (aClock * 6) ]
		ifFalse: [ 20 + ((aClock - 114) * 6) ].
	self addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement
			text: '$' , (aClock printPaddedWith: $0 to: 2 base: 16)
			size: 8 color: Color gray);
		relocate: x @ (aRow = 0 ifTrue: [ 25 ] ifFalse: [ 83 ]);
		yourself)
]

{ #category : #'building' }
GT4AmigaDMATimelineElement >> labelAt: aPosition text: aString [
	self addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement text: aString size: 8 color: Color gray);
		relocate: aPosition;
		yourself)
]

{ #category : #'building' }
GT4AmigaDMATimelineElement >> buildLegend [
	| specs x |
	specs := {
		'refresh' -> self refreshColor.
		'disk' -> self diskColor.
		'audio' -> self audioColor.
		'sprites' -> self spriteColor.
		'bitplanes' -> (self bitplaneColor: 2).
		'free (odd)' -> (Color gray alpha: 0.12).
		'free (even = 68000)' -> (Color gray alpha: 0.28) }.
	x := 20.
	specs do: [ :pair |
		self addChild: (BlElement new
			size: 10 @ 10;
			background: pair value;
			border: (BlBorder paint: (Color gray alpha: 0.5) width: 1);
			relocate: x @ 152;
			yourself).
		self labelAt: (x + 14) @ 151 text: pair key.
		x := x + 14 + (pair key size * 5) + 14 ].
	self labelAt: 20 @ 172
		text: 'pale = channel disabled in DMACON (the slot stands open to the Copper, the blitter and the 68000) - hover a slot for its story, click it for its register'
]

{ #category : #'accessing' }
GT4AmigaDMATimelineElement >> refreshColor [ ^ Color gray alpha: 0.8 ]

{ #category : #'accessing' }
GT4AmigaDMATimelineElement >> diskColor [ ^ Color r: 0.2 g: 0.55 b: 0.25 ]

{ #category : #'accessing' }
GT4AmigaDMATimelineElement >> audioColor [ ^ Color r: 0.85 g: 0.6 b: 0.1 ]

{ #category : #'accessing' }
GT4AmigaDMATimelineElement >> spriteColor [ ^ Color r: 0.55 g: 0.3 b: 0.75 ]

{ #category : #'accessing' }
GT4AmigaDMATimelineElement >> bitplaneColor: aPlane [
	^ Color r: 0.1 g: 0.25 + (aPlane * 0.08) b: 0.95
]

{ #category : #'testing' }
GT4AmigaDMATimelineElement >> bit: aFieldName [
	"The cached DMACON state of one field - no serial I/O (UI thread safe)."
	^ dmacon value
		ifNil: [ false ]
		ifNotNil: [ :v | ((dmacon fieldNamed: aFieldName) valueIn: v) = 1 ]
]

{ #category : #'computing' }
GT4AmigaDMATimelineElement >> fetchWindow [
	"The live bitplane fetch parameters {start. lastClock. hires. planes},
	 or nil when they are unknown or no planes are on. The last fetch
	 group runs to DDFSTOP+7 and the hardware stop at $D8 caps everything
	 (AHRM figure 6-9); starts below the $18 hardware stop clamp to it."
	| v0 planes hires strt stop |
	v0 := bplcon0 value.
	v0 ifNil: [ ^ nil ].
	planes := (bplcon0 fieldNamed: 'BPU') valueIn: v0.
	planes = 0 ifTrue: [ ^ nil ].
	hires := ((bplcon0 fieldNamed: 'HIRES') valueIn: v0) = 1.
	strt := ddfstrt value.
	stop := ddfstop value.
	(strt isNil or: [ stop isNil ]) ifTrue: [ ^ nil ].
	^ { (strt max: 16r18). (stop + 7) min: 16rD7. hires. planes }
]

{ #category : #'computing' }
GT4AmigaDMATimelineElement >> computeOwners [
	"One symbol or kind->detail association per color clock $00-$E2, from
	 the CACHED register values. Fixed slots per AHRM figure 6-9; bitplane
	 fetch order per figures 6-11 (lores: planes 1-4 odd slots, 5-6 steal
	 the 68000's even ones) and 6-12 (hires: every slot). Bitplane DMA
	 takes precedence over sprites when the window starts early."
	| result window |
	result := Array new: 227 withAll: #free.
	#(16r01 16r03 16r05 16r07) do: [ :c | result at: c + 1 put: #refresh ].
	#(16r09 16r0B 16r0D) do: [ :c | result at: c + 1 put: #disk ].
	0 to: 3 do: [ :n | result at: 16r0F + (2 * n) + 1 put: #audio -> n ].
	0 to: 7 do: [ :n |
		result at: 16r17 + (4 * n) + 1 put: #sprite -> n.
		result at: 16r19 + (4 * n) + 1 put: #sprite -> n ].
	window := self fetchWindow.
	window ifNotNil: [
		| strt last hires planes |
		strt := window first. last := window second.
		hires := window third. planes := window fourth.
		strt to: last do: [ :c |
			| plane |
			plane := hires
				ifTrue: [ #(4 2 3 1) at: (c - strt) \\ 4 + 1 ]
				ifFalse: [ #(0 4 6 2 0 3 5 1) at: (c - strt) \\ 8 + 1 ].
			(plane > 0 and: [ plane <= planes ])
				ifTrue: [ result at: c + 1 put: #bitplane -> plane ] ] ].
	^ result
]

{ #category : #'computing' }
GT4AmigaDMATimelineElement >> ownerEnabled: anOwner [
	"Does the live DMACON actually feed this slot's channel?"
	anOwner = #refresh ifTrue: [ ^ true ].
	anOwner = #free ifTrue: [ ^ true ].
	(self bit: 'DMAEN') ifFalse: [ ^ false ].
	anOwner = #disk ifTrue: [ ^ self bit: 'DSKEN' ].
	anOwner key = #audio ifTrue: [ ^ self bit: 'AUD' , anOwner value printString , 'EN' ].
	anOwner key = #sprite ifTrue: [ ^ self bit: 'SPREN' ].
	anOwner key = #bitplane ifTrue: [ ^ self bit: 'BPLEN' ].
	^ true
]

{ #category : #'computing' }
GT4AmigaDMATimelineElement >> ownerColor: anOwner [
	anOwner = #refresh ifTrue: [ ^ self refreshColor ].
	anOwner = #free ifTrue: [ ^ Color gray alpha: 0.12 ].
	anOwner = #disk ifTrue: [ ^ self diskColor ].
	anOwner key = #audio ifTrue: [ ^ self audioColor ].
	anOwner key = #sprite ifTrue: [ ^ self spriteColor ].
	anOwner key = #bitplane ifTrue: [ ^ self bitplaneColor: anOwner value ].
	^ Color transparent
]

{ #category : #'computing' }
GT4AmigaDMATimelineElement >> slotDescription: aClock [
	| owner s |
	owner := owners ifNil: [ #free ] ifNotNil: [ owners at: aClock + 1 ].
	s := WriteStream on: String new.
	s nextPutAll: 'slot $'; nextPutAll: (aClock printPaddedWith: $0 to: 2 base: 16); nextPutAll: ' - '.
	owner = #refresh
		ifTrue: [ s nextPutAll: 'memory refresh (always taken)' ].
	owner = #disk
		ifTrue: [ s nextPutAll: 'disk DMA' ].
	owner = #free
		ifTrue: [ s nextPutAll: 'free: Copper, blitter'.
			aClock even ifTrue: [ s nextPutAll: ' - and the even slot the 68000 uses for memory access' ] ].
	(owner isKindOf: Association) ifTrue: [
		owner key = #audio ifTrue: [ s nextPutAll: 'audio channel ', owner value printString, ' DMA (one word)' ].
		owner key = #sprite ifTrue: [ s nextPutAll: 'sprite ', owner value printString, ' DMA (one of its two words)' ].
		owner key = #bitplane ifTrue: [ s nextPutAll: 'bitplane ', owner value printString, ' data fetch' ] ].
	(self ownerEnabled: owner)
		ifFalse: [ s nextPutAll: ' - DISABLED in DMACON, so the slot stands open to others' ].
	^ s contents
]

{ #category : #'computing' }
GT4AmigaDMATimelineElement >> summaryString [
	| s window bplCount freeCount |
	s := WriteStream on: String new.
	s nextPutAll: '227 color clocks per scan line (280 ns each) - '.
	window := self fetchWindow.
	window
		ifNil: [ s nextPutAll: 'bitplane fetch state unknown (no copper list read yet)' ]
		ifNotNil: [
			s nextPutAll: (window third ifTrue: [ 'hires' ] ifFalse: [ 'lores' ]).
			s nextPutAll: ', '; print: window fourth; nextPutAll: ' bitplanes, DDFSTRT $'.
			s nextPutAll: (ddfstrt value printPaddedWith: $0 to: 2 base: 16).
			s nextPutAll: ' DDFSTOP $'; nextPutAll: (ddfstop value printPaddedWith: $0 to: 2 base: 16) ].
	owners ifNotNil: [
		bplCount := owners count: [ :o | (o isKindOf: Association) and: [ o key = #bitplane ] ].
		freeCount := owners count: [ :o | o = #free ].
		s nextPutAll: ' - slots: 4 refresh + 3 disk + 4 audio + 16 sprite + '.
		s print: bplCount; nextPutAll: ' bitplane + '; print: freeCount; nextPutAll: ' free' ].
	^ s contents
]

{ #category : #'accessing' }
GT4AmigaDMATimelineElement >> observationNeeds [
	"What the shared gateway must keep fresh for me: the four registers
	 that drive the figure. The three copper-derived reads (BPLCON0/DDF*)
	 share the gateway's one cached copper-list snapshot per sweep."
	^ { dmacon. bplcon0. ddfstrt. ddfstop }
]

{ #category : #'testing' }
GT4AmigaDMATimelineElement >> isObserving [
	^ machine catalog observer isWatching: self
]

{ #category : #'observing' }
GT4AmigaDMATimelineElement >> startObserving [
	machine catalog announcer unsubscribe: self.
	machine catalog announcer when: GT4AmigaRegistersRefreshed send: #onRefreshed to: self.
	machine catalog observer watch: self observationNeeds for: self
]

{ #category : #'observing' }
GT4AmigaDMATimelineElement >> stopObserving [
	machine catalog announcer unsubscribe: self.
	machine catalog observer unwatch: self
]

{ #category : #'updating' }
GT4AmigaDMATimelineElement >> onRefreshed [
	"Announced from the gateway: hop to the UI thread to repaint."
	self enqueueTask: (BlTaskAction new action: [ self updateFromCache ])
]

{ #category : #'updating' }
GT4AmigaDMATimelineElement >> updateFromCache [
	owners := self computeOwners.
	0 to: 226 do: [ :clock |
		| owner color |
		owner := owners at: clock + 1.
		color := self ownerColor: owner.
		(owner = #free and: [ clock even ]) ifTrue: [ color := Color gray alpha: 0.28 ].
		(self ownerEnabled: owner) ifFalse: [ color := color alpha: 0.18 ].
		(cells at: clock + 1) background: color ].
	summaryLabel text: (GT4AmigaControlPanelElement
		text: self summaryString size: 10 color: Color darkGray)
]
