"
The AHRM-style bit diagram of ONE chip register: sixteen bit cells (15 down to 0) grouped by named field, the field mnemonic under its cells and, for multi-bit fields, the decoded value. This is the graphical face every register gets in the inspector - the same visual language as the DMACON/INTENA control panel, extended to multi-bit fields (BPU, VSTART, R/G/B...) and to field-less registers, which simply show their raw 16 bits. COLORxx registers also get a live swatch of the decoded RGB in the header.

Each cell has a kind: #switch (a SET/CLR flag - a click queues a toggle), #led (read-only indicator like BBUSY, orange when on), #locked (toggleable in theory, but turning it off would cut the monitor link - red border, not clickable), #protocol (the SETCLR bit: on reads it carries no state), and #plain (any other bit, read-only). Bits outside every field render pale but still show their value.

Threading contract (project rule: no serial I/O on the UI thread): I render only the register cache. One background worker - started when I enter the scene graph, stopped when I leave it - drains my click queue, polls the register every 2 seconds and announces GT4AmigaRegistersRefreshed on the catalog announcer; the announcement handler hops back to the UI thread to repaint, so other listeners (the control panel, the DMA timeline) also stay in sync.

Open me with: GT4AmigaRegisterDiagramElement onRegister: (GT4AmigaChipRegisters default at: 'DMACON') - or just inspect any register and pick the Diagram view.
"
Class {
	#name : #GT4AmigaRegisterDiagramElement,
	#superclass : #BlElement,
	#instVars : [
		'register',
		'queue',
		'mutex',
		'running',
		'valueLabel',
		'swatch',
		'cells',
		'decodedLabels',
		'generation'
	],
	#category : #'GT4Amiga-Hardware-UI'
}

{ #category : #'instance creation' }
GT4AmigaRegisterDiagramElement class >> onRegister: aRegister [
	^ self new setRegister: aRegister
]

{ #category : #'instance creation' }
GT4AmigaRegisterDiagramElement >> setRegister: aRegister [
	register := aRegister.
	queue := OrderedCollection new.
	mutex := Mutex new.
	running := false.
	generation := 0.
	cells := OrderedCollection new.
	decodedLabels := Dictionary new.
	self layout: BlLinearLayout vertical.
	self constraintsDo: [ :c |
		c horizontal fitContent.
		c vertical fitContent ].
	self padding: (BlInsets all: 8).
	self addChild: self buildHeader.
	self addChild: self buildBitRow.
	self updateFromCache.
	self addEventHandlerOn: BlElementAddedToSceneGraphEvent do: [ :evt | self startWorker ].
	self addEventHandlerOn: BlElementRemovedFromSceneGraphEvent do: [ :evt | self stopWorker ]
]

{ #category : #'accessing' }
GT4AmigaRegisterDiagramElement >> register [
	^ register
]

{ #category : #'accessing' }
GT4AmigaRegisterDiagramElement >> isRunning [
	^ running
]

{ #category : #'testing' }
GT4AmigaRegisterDiagramElement >> isColorRegister [
	^ (register fields collect: [ :f | f name ]) asArray = #('R' 'G' 'B')
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> buildHeader [
	| header |
	header := BlElement new
		layout: BlLinearLayout horizontal alignCenter;
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ];
		yourself.
	header addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement
			text: register name , '  ' , register addressString , '   '
			size: 13
			color: Color black);
		yourself).
	valueLabel := BlTextElement new
		text: (GT4AmigaControlPanelElement text: '?' size: 13 color: Color blue muchDarker);
		margin: (BlInsets left: 8);
		yourself.
	header addChild: valueLabel.
	self isColorRegister ifTrue: [
		swatch := BlElement new
			size: 16 @ 16;
			margin: (BlInsets left: 10);
			border: (BlBorder paint: Color darkGray width: 1);
			yourself.
		header addChild: swatch ].
	header addAptitude: (BrGlamorousWithLabelTooltipAptitude text: register description).
	^ header
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> buildBitRow [
	| row |
	row := BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ];
		margin: (BlInsets top: 8);
		yourself.
	self bitGroups do: [ :g | row addChild: (self buildGroupFor: g) ].
	^ row
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> bitGroups [
	"Walk bits 15..0 and split them into field groups; consecutive bits
	 belonging to no field collapse into one anonymous group."
	| groups bit field run |
	groups := OrderedCollection new.
	bit := 15.
	[ bit >= 0 ] whileTrue: [
		field := self fieldAtBit: bit.
		field
			ifNotNil: [
				groups add: { field. field msb. field lsb }.
				bit := field lsb - 1 ]
			ifNil: [
				run := bit.
				[ run >= 0 and: [ (self fieldAtBit: run) isNil ] ] whileTrue: [ run := run - 1 ].
				groups add: { nil. bit. run + 1 }.
				bit := run ] ].
	^ groups
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> fieldAtBit: aBit [
	^ register fields
		detect: [ :f | aBit between: f lsb and: f msb ]
		ifNone: [ nil ]
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> buildGroupFor: aGroupArray [
	| field msb lsb kind group bitsRow |
	field := aGroupArray first.
	msb := aGroupArray second.
	lsb := aGroupArray third.
	kind := field ifNil: [ #unused ] ifNotNil: [ self kindFor: field ].
	group := BlElement new
		layout: BlLinearLayout vertical alignCenter;
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ];
		margin: (BlInsets right: 3);
		yourself.
	bitsRow := BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ];
		yourself.
	msb to: lsb by: -1 do: [ :bit |
		bitsRow addChild: (self buildCellFor: bit field: field kind: kind) ].
	group addChild: bitsRow.
	field ifNotNil: [
		group addChild: (BlTextElement new
			text: (GT4AmigaControlPanelElement text: field name size: 9 color: Color darkGray);
			margin: (BlInsets top: 2);
			yourself).
		field isFlag ifFalse: [
			| decoded |
			decoded := BlTextElement new
				text: (GT4AmigaControlPanelElement text: '?' size: 9 color: Color blue muchDarker);
				yourself.
			decodedLabels at: field put: decoded.
			group addChild: decoded ] ].
	^ group
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> buildCellFor: aBit field: aFieldOrNil kind: aKind [
	| stack box text |
	stack := BlElement new
		layout: BlLinearLayout vertical alignCenter;
		constraintsDo: [ :c |
			c horizontal fitContent.
			c vertical fitContent ];
		yourself.
	stack addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement text: aBit printString size: 7 color: Color gray);
		yourself).
	box := BlElement new
		size: 22 @ 20;
		layout: BlLinearLayout horizontal alignCenter;
		margin: (BlInsets top: 1);
		border: (BlBorder paint: (self borderColorFor: aKind) width: (self borderWidthFor: aKind));
		yourself.
	text := BlTextElement new
		text: (GT4AmigaControlPanelElement text: '?' size: 11 color: Color gray);
		yourself.
	box addChild: text.
	aKind = #switch ifTrue: [
		box addEventHandlerOn: BlClickEvent do: [ :evt |
			evt consumed: true.
			self toggleField: aFieldOrNil ] ].
	box addAptitude: (BrGlamorousWithLabelTooltipAptitude
		text: (self tooltipForBit: aBit field: aFieldOrNil kind: aKind)).
	cells add: { aBit. box. text. aFieldOrNil. aKind }.
	stack addChild: box.
	^ stack
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> kindFor: aField [
	register mode == #setClear ifFalse: [ ^ #plain ].
	aField name = 'SETCLR' ifTrue: [ ^ #protocol ].
	((GT4AmigaRegisterPanelElement readOnlyFieldsFor: register name) includes: aField name)
		ifTrue: [ ^ #led ].
	((GT4AmigaRegisterPanelElement lockedFieldsFor: register name) includes: aField name)
		ifTrue: [ ^ #locked ].
	aField isFlag ifFalse: [ ^ #plain ].
	^ #switch
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> borderColorFor: aKind [
	aKind = #locked ifTrue: [ ^ Color red ].
	(aKind = #unused or: [ aKind = #protocol ]) ifTrue: [ ^ Color gray alpha: 0.4 ].
	^ Color darkGray
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> borderWidthFor: aKind [
	^ aKind = #locked
		ifTrue: [ 2 ]
		ifFalse: [ 1 ]
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> tooltipForBit: aBit field: aFieldOrNil kind: aKind [
	| suffix |
	aFieldOrNil ifNil: [ ^ 'bit ' , aBit printString , ' (sin uso)' ].
	suffix := aKind = #switch
		ifTrue: [ ' [clic para conmutar]' ]
		ifFalse: [ aKind = #led
			ifTrue: [ ' [solo lectura]' ]
			ifFalse: [ aKind = #locked
				ifTrue: [ ' [BLOQUEADO: apagarlo cortaria el enlace del monitor]' ]
				ifFalse: [ aKind = #protocol
					ifTrue: [ ' [bit de protocolo, no estado]' ]
					ifFalse: [ '' ] ] ] ].
	^ aFieldOrNil name , ' (bit ' , aFieldOrNil bitsString , '): ' , aFieldOrNil description , suffix
]

{ #category : #'actions' }
GT4AmigaRegisterDiagramElement >> toggleField: aField [
	| reg fieldName turnOn |
	reg := register.
	fieldName := aField name.
	turnOn := (aField valueIn: (register value ifNil: [ 0 ])) = 0.
	self enqueue: [
		turnOn
			ifTrue: [ reg enable: fieldName ]
			ifFalse: [ reg disable: fieldName ] ]
]

{ #category : #'worker' }
GT4AmigaRegisterDiagramElement >> enqueue: aBlock [
	mutex critical: [ queue addLast: aBlock ]
]

{ #category : #'worker' }
GT4AmigaRegisterDiagramElement >> startWorker [
	"The generation stamp retires a previous loop that survived a quick
	 detach/re-attach (inspector tabs, exporters) while blocked in serial
	 I/O - re-arming the shared running flag must not leave two loops."
	| myGeneration |
	running ifTrue: [ ^ self ].
	running := true.
	generation := generation + 1.
	myGeneration := generation.
	register catalog announcer unsubscribe: self.
	register catalog announcer when: GT4AmigaRegistersRefreshed send: #onRefreshed to: self.
	[ self workerLoopGeneration: myGeneration ]
		forkAt: Processor userBackgroundPriority
		named: 'GT4Amiga register diagram worker'
]

{ #category : #'worker' }
GT4AmigaRegisterDiagramElement >> stopWorker [
	running := false.
	register catalog announcer unsubscribe: self
]

{ #category : #'worker' }
GT4AmigaRegisterDiagramElement >> workerLoopGeneration: myGeneration [
	| idleMs |
	idleMs := 0.
	self pollRegister.
	[ running and: [ generation = myGeneration ] ] whileTrue: [
		| action |
		action := mutex critical: [
			queue isEmpty
				ifTrue: [ nil ]
				ifFalse: [ queue removeFirst ] ].
		action
			ifNotNil: [
				[ action value ] on: Error do: [ :e | ].
				self pollRegister.
				idleMs := 0 ]
			ifNil: [
				(Delay forMilliseconds: 200) wait.
				idleMs := idleMs + 200.
				idleMs >= 2000 ifTrue: [
					self pollRegister.
					idleMs := 0 ] ] ]
]

{ #category : #'worker' }
GT4AmigaRegisterDiagramElement >> pollRegister [
	"Serial I/O - worker only. A dead link must not kill the loop."
	[ register read.
	register catalog announcer announce: GT4AmigaRegistersRefreshed new ]
		on: Error
		do: [ :e | ]
]

{ #category : #'updating' }
GT4AmigaRegisterDiagramElement >> onRefreshed [
	"Announced from a worker: hop to the UI thread to repaint."
	self enqueueTask: (BlTaskAction new action: [ self updateFromCache ])
]

{ #category : #'updating' }
GT4AmigaRegisterDiagramElement >> updateFromCache [
	| v |
	v := register value.
	valueLabel text: (GT4AmigaControlPanelElement
		text: register valueString
		size: 13
		color: Color blue muchDarker).
	cells do: [ :entry | self updateCell: entry value: v ].
	decodedLabels keysAndValuesDo: [ :field :label |
		label text: (GT4AmigaControlPanelElement
			text: (v
				ifNil: [ '?' ]
				ifNotNil: [ :vv | (field valueIn: vv) printString ])
			size: 9
			color: Color blue muchDarker) ].
	(swatch isNil or: [ v isNil ]) ifFalse: [
		swatch background: (Color
			r: ((v bitShift: -8) bitAnd: 15) / 15
			g: ((v bitShift: -4) bitAnd: 15) / 15
			b: (v bitAnd: 15) / 15) ]
]

{ #category : #'updating' }
GT4AmigaRegisterDiagramElement >> updateCell: anEntry value: aValueOrNil [
	| bit box text kind bitVal background textColor pale |
	bit := anEntry first.
	box := anEntry second.
	text := anEntry third.
	kind := anEntry fifth.
	aValueOrNil ifNil: [
		box background: Color white.
		^ text text: (GT4AmigaControlPanelElement text: '?' size: 11 color: Color gray) ].
	bitVal := (aValueOrNil bitShift: bit negated) bitAnd: 1.
	pale := kind = #unused or: [ kind = #protocol ].
	bitVal = 1
		ifTrue: [
			background := pale
				ifTrue: [ Color gray ]
				ifFalse: [ kind = #led
					ifTrue: [ Color orange ]
					ifFalse: [ Color green muchDarker ] ].
			textColor := Color white ]
		ifFalse: [
			background := pale
				ifTrue: [ Color lightGray alpha: 0.3 ]
				ifFalse: [ Color white ].
			textColor := pale
				ifTrue: [ Color gray ]
				ifFalse: [ Color darkGray ] ].
	box background: background.
	text text: (GT4AmigaControlPanelElement text: bitVal printString size: 11 color: textColor)
]
