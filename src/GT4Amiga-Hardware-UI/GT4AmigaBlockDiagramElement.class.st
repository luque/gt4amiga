"
The A500 as a clickable block diagram: the 68000, the three custom chips, the CIAs, the three memory regions, and the buses between them. Every box is a door into the model - clicking it spawns the corresponding GT4AmigaChip or GT4AmigaMemoryRegion in the inspector - and the DMA arrows are LIVE: each lights up when the DMACON bits that drive it are enabled (bitplanes/sprites toward Denise, audio/disk toward Paula, the RAM funnel under the DMAEN master), and the Copper and blitter LEDs sit inside Agnus, where those engines physically live. Kill DMAEN in the control panel and watch every arrow go dark.

Threading contract (project rule: no serial I/O on the UI thread):
- a background worker polls DMACON every 2 seconds while I am in the scene graph and announces GT4AmigaRegistersRefreshed on the catalog announcer (the same announcement the control panel uses, so either element keeps the other fresh);
- the announcement handler repaints arrows and LEDs from the register CACHE via an enqueued Bloc task;
- the worker starts when I enter the scene graph and stops when I leave it, so closing the inspector leaves no orphan process behind.

Open me with: GT4AmigaBlockDiagramElement onMachine: GT4AmigaMachine default - or inspect the machine and pick the Block diagram view.
"
Class {
	#name : #GT4AmigaBlockDiagramElement,
	#superclass : #BlElement,
	#instVars : [
		'machine',
		'dmacon',
		'running',
		'litLines',
		'copLed',
		'bltLed'
	],
	#category : #'GT4Amiga-Hardware-UI'
}

{ #category : #'instance creation' }
GT4AmigaBlockDiagramElement class >> onMachine: aMachine [
	^ self new setMachine: aMachine
]

{ #category : #'instance creation' }
GT4AmigaBlockDiagramElement >> setMachine: aMachine [
	machine := aMachine.
	dmacon := machine catalog at: 'DMACON'.
	running := false.
	litLines := OrderedCollection new.
	self size: 680 @ 360.
	self buildDiagram.
	self updateFromCache.
	self addEventHandlerOn: BlElementAddedToSceneGraphEvent do: [ :evt | self startWorker ].
	self addEventHandlerOn: BlElementRemovedFromSceneGraphEvent do: [ :evt | self stopWorker ]
]

{ #category : #'building' }
GT4AmigaBlockDiagramElement >> buildDiagram [
	| cpu ciaa ciab slow agnus chipRam denise paula rom |
	cpu := self boxTitled: '68000' sub: 'CPU' at: 30 @ 40 size: 110 @ 60
		tint: (Color gray alpha: 0.12) spawning: (machine chipNamed: '68000').
	ciaa := self boxTitled: 'CIA-A' sub: '8520' at: 30 @ 170 size: 52 @ 50
		tint: (Color gray alpha: 0.12) spawning: (machine chipNamed: 'CIA-A').
	ciab := self boxTitled: 'CIA-B' sub: '8520' at: 88 @ 170 size: 52 @ 50
		tint: (Color gray alpha: 0.12) spawning: (machine chipNamed: 'CIA-B').
	slow := self boxTitled: 'Slow RAM' sub: '512 KB' at: 30 @ 280 size: 110 @ 50
		tint: (Color blue alpha: 0.08) spawning: (machine regionNamed: 'Slow RAM').
	agnus := self boxTitled: 'Agnus' sub: '8371 - DMA' at: 280 @ 40 size: 140 @ 120
		tint: (Color orange alpha: 0.12) spawning: (machine chipNamed: 'Agnus').
	chipRam := self boxTitled: 'Chip RAM' sub: '512 KB' at: 280 @ 260 size: 140 @ 60
		tint: (Color blue alpha: 0.08) spawning: (machine regionNamed: 'Chip RAM').
	denise := self boxTitled: 'Denise' sub: '8362 - video' at: 520 @ 40 size: 120 @ 60
		tint: (Color orange alpha: 0.12) spawning: (machine chipNamed: 'Denise').
	paula := self boxTitled: 'Paula' sub: '8364 - audio/IRQ' at: 520 @ 170 size: 120 @ 60
		tint: (Color orange alpha: 0.12) spawning: (machine chipNamed: 'Paula').
	rom := self boxTitled: 'Kickstart' sub: 'ROM 256 KB' at: 520 @ 290 size: 120 @ 50
		tint: (Color green alpha: 0.08) spawning: (machine regionNamed: 'Kickstart ROM').

	"Static buses (always drawn, never lit): the CPU side of the machine."
	self addChildFirst: (self busFrom: cpu to: agnus).
	self addChildFirst: (self busFrom: cpu to: ciaa).
	self addChildFirst: (self busFrom: cpu to: ciab).
	self addChildFirst: (self busFrom: cpu to: slow).
	self addChildFirst: (self busFrom: cpu to: rom).

	"Live DMA arrows: lit by the DMACON bits the worker keeps fresh."
	self litLineFrom: chipRam to: agnus
		when: [ self bit: 'DMAEN' ].
	self litLineFrom: agnus to: denise
		when: [ (self bit: 'DMAEN') and: [ (self bit: 'BPLEN') or: [ self bit: 'SPREN' ] ] ].
	self litLineFrom: agnus to: paula
		when: [ (self bit: 'DMAEN') and: [
			(self bit: 'DSKEN') or: [
				#('AUD0EN' 'AUD1EN' 'AUD2EN' 'AUD3EN') anySatisfy: [ :n | self bit: n ] ] ] ].

	self labelAt: 435 @ 48 text: 'bitplanes + sprites'.
	self labelAt: 445 @ 158 text: 'audio + disk'.
	self labelAt: 358 @ 208 text: 'DMA'.

	"The Copper and the blitter are DMA engines INSIDE Agnus."
	copLed := self ledLabeled: 'COP'.
	bltLed := self ledLabeled: 'BLT'.
	agnus addChild: ((BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		margin: (BlInsets top: 6);
		yourself)
			addChildren: { copLed. bltLed };
			yourself)
]

{ #category : #'building' }
GT4AmigaBlockDiagramElement >> boxTitled: aTitle sub: aSub at: aPosition size: anExtent tint: aColor spawning: aModelObject [
	| box |
	box := BlElement new
		geometry: (BlRoundedRectangleGeometry cornerRadius: 6);
		background: aColor;
		border: (BlBorder paint: Color darkGray width: 1);
		layout: BlLinearLayout vertical alignCenter;
		size: anExtent;
		relocate: aPosition;
		padding: (BlInsets top: 8);
		yourself.
	box addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement text: aTitle size: 12 color: Color darkGray);
		yourself).
	box addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement text: aSub size: 9 color: Color gray);
		margin: (BlInsets top: 2);
		yourself).
	box addEventHandlerOn: BlClickEvent do: [ :evt |
		evt consumed: true.
		box phlow spawnObject: aModelObject ].
	box addAptitude: (BrGlamorousWithLabelTooltipAptitude text: aModelObject description).
	self addChild: box.
	^ box
]

{ #category : #'building' }
GT4AmigaBlockDiagramElement >> busFrom: aBox to: anotherBox [
	^ BlLineElement new
		border: (BlBorder paint: (Color gray alpha: 0.5) width: 1);
		fromAnchor: (BlElementCenterAnchor element: aBox);
		toAnchor: (BlElementCenterAnchor element: anotherBox);
		yourself
]

{ #category : #'building' }
GT4AmigaBlockDiagramElement >> litLineFrom: aBox to: anotherBox when: aPredicate [
	| line |
	line := BlLineElement new
		border: (BlBorder paint: (Color gray alpha: 0.4) width: 1);
		fromAnchor: (BlElementCenterAnchor element: aBox);
		toAnchor: (BlElementCenterAnchor element: anotherBox);
		yourself.
	litLines add: line -> aPredicate.
	self addChildFirst: line.
	^ line
]

{ #category : #'building' }
GT4AmigaBlockDiagramElement >> labelAt: aPosition text: aString [
	self addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement text: aString size: 9 color: Color gray);
		relocate: aPosition;
		yourself)
]

{ #category : #'building' }
GT4AmigaBlockDiagramElement >> ledLabeled: aString [
	| led |
	led := BlElement new
		layout: BlLinearLayout horizontal alignCenter;
		constraintsDo: [ :c | c horizontal fitContent. c vertical fitContent ];
		margin: (BlInsets left: 4 right: 4);
		yourself.
	led addChild: (BlElement new
		size: 10 @ 10;
		geometry: BlCircleGeometry new;
		border: (BlBorder paint: Color darkGray width: 1);
		background: Color veryDarkGray;
		yourself).
	led addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement text: aString size: 8 color: Color gray);
		margin: (BlInsets left: 3);
		yourself).
	^ led
]

{ #category : #'testing' }
GT4AmigaBlockDiagramElement >> bit: aFieldName [
	"The cached DMACON state of one field - no serial I/O (UI thread safe)."
	^ dmacon value
		ifNil: [ false ]
		ifNotNil: [ :v | ((dmacon fieldNamed: aFieldName) valueIn: v) = 1 ]
]

{ #category : #'accessing' }
GT4AmigaBlockDiagramElement >> isRunning [
	^ running
]

{ #category : #'worker' }
GT4AmigaBlockDiagramElement >> startWorker [
	running ifTrue: [ ^ self ].
	running := true.
	machine catalog announcer unsubscribe: self.
	machine catalog announcer when: GT4AmigaRegistersRefreshed send: #onRefreshed to: self.
	[ self workerLoop ]
		forkAt: Processor userBackgroundPriority
		named: 'GT4Amiga block diagram worker'
]

{ #category : #'worker' }
GT4AmigaBlockDiagramElement >> stopWorker [
	running := false.
	machine catalog announcer unsubscribe: self
]

{ #category : #'worker' }
GT4AmigaBlockDiagramElement >> workerLoop [
	"Poll DMACON every 2 seconds and announce; a dead link must not kill
	 the loop (read keeps the previous cache on nil)."
	[ running ] whileTrue: [
		[ dmacon read.
		machine catalog announcer announce: GT4AmigaRegistersRefreshed new ]
			on: Error do: [ :e | ].
		(Delay forMilliseconds: 2000) wait ]
]

{ #category : #'updating' }
GT4AmigaBlockDiagramElement >> onRefreshed [
	"Announced from a worker: hop to the UI thread to repaint."
	self enqueueTask: (BlTaskAction new action: [ self updateFromCache ])
]

{ #category : #'updating' }
GT4AmigaBlockDiagramElement >> updateFromCache [
	litLines do: [ :assoc |
		assoc key border: (assoc value value
			ifTrue: [ BlBorder paint: Color orange width: 3 ]
			ifFalse: [ BlBorder paint: (Color gray alpha: 0.4) width: 1 ]) ].
	copLed children first background:
		(((self bit: 'DMAEN') and: [ self bit: 'COPEN' ])
			ifTrue: [ Color orange ] ifFalse: [ Color veryDarkGray ]).
	bltLed children first background:
		(((self bit: 'DMAEN') and: [ self bit: 'BLTEN' ])
			ifTrue: [ Color orange ] ifFalse: [ Color veryDarkGray ])
]
