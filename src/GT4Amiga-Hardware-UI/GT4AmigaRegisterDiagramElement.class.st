"
The AHRM-style bit diagram of ONE chip register, as a live figure that both REFLECTS and (where the domain says it is safe) WRITES: sixteen bit cells (15 down to 0) grouped by named field, the field mnemonic under its cells and, for multi-bit fields, the decoded value. Field-less registers show their raw 16 bits; COLORxx get a live RGB swatch in the header.

Writing is gated by the model's write-safety policy (GT4AmigaChipRegister>>writeSafetyOf:), so the same figure can sit on EVERY register without letting casual play brick the machine. Each cell's kind, from that policy:
  #writable       a latching bit safe to toggle (DMACON channels, the non-critical INTENA/ADKCON bits) - CLICKABLE; a click enqueues the write on my worker
  #transient      writable in theory, but the Workbench copper rewrites this register every frame so the write would not persist (COLORxx, BPLCONx, DDF/DIW, modulos) - shown with an amber border, not clickable
  #linkCritical   a write would cut the monitor's own link (INTEN/RBF/TBE/PORTS, ADKCON UARTBRK) - red border, locked
  #systemCritical a write would hold a task ('Software error - task held'): the whole INTREQ register (a write injects a live interrupt), INTENA VERTB/EXTER - red border, locked
  #readOnly       a read-mode register or a hardware-set indicator (BBUSY/BZERO) - LED style, not clickable
  #protocol       the SETCLR command bit - pale, carries no state
  #unused         a bit outside every field - pale, still showing its value

Threading contract (project rule: no serial I/O on the UI thread): I run NO polling loop of my own. On entering the scene graph I subscribe to the catalog's shared serial gateway (GT4AmigaChipRegisters>>observer, a GT4AmigaHardwareObserver) declaring my observationNeeds - just my one register; the gateway keeps it fresh for me (and for every other view, with a single de-duplicated reader) and announces GT4AmigaRegistersRefreshed, which repaints me from the CACHE on the UI thread. A click does not talk to the machine either: it hands a toggle block to the gateway's write queue, serialized with the reads. On leaving the scene graph I unwatch. This is the first view migrated to the shared-observer model, so no two live views ever contend for the monitor's single socket.

Open me with: GT4AmigaRegisterDiagramElement onRegister: (GT4AmigaChipRegisters default at: 'DMACON') - or just inspect any register and pick the Diagram view.
"
Class {
	#name : #GT4AmigaRegisterDiagramElement,
	#superclass : #BlElement,
	#instVars : [
		'register',
		'valueLabel',
		'swatch',
		'cells',
		'decodedLabels'
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
	self addEventHandlerOn: BlElementAddedToSceneGraphEvent do: [ :evt | self startObserving ].
	self addEventHandlerOn: BlElementRemovedFromSceneGraphEvent do: [ :evt | self stopObserving ]
]

{ #category : #'accessing' }
GT4AmigaRegisterDiagramElement >> register [
	^ register
]

{ #category : #'accessing' }
GT4AmigaRegisterDiagramElement >> observationNeeds [
	"What the shared gateway must keep fresh for me: just my register."
	^ { register }
]

{ #category : #'testing' }
GT4AmigaRegisterDiagramElement >> isObserving [
	^ register catalog observer isWatching: self
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
	kind := field ifNil: [ #unused ] ifNotNil: [ register writeSafetyOf: field ].
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
			text: (GT4AmigaControlPanelElement text: field name size: 9 color: (self labelColorFor: kind));
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
	(aKind = #writable and: [ aFieldOrNil notNil ]) ifTrue: [
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
GT4AmigaRegisterDiagramElement >> borderColorFor: aKind [
	(aKind = #linkCritical or: [ aKind = #systemCritical ]) ifTrue: [ ^ Color red ].
	aKind = #transient ifTrue: [ ^ Color orange muchDarker ].
	(aKind = #unused or: [ aKind = #protocol ]) ifTrue: [ ^ Color gray alpha: 0.4 ].
	^ Color darkGray
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> borderWidthFor: aKind [
	^ (aKind = #linkCritical or: [ aKind = #systemCritical ])
		ifTrue: [ 2 ]
		ifFalse: [ 1 ]
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> labelColorFor: aKind [
	(aKind = #linkCritical or: [ aKind = #systemCritical ]) ifTrue: [ ^ Color red muchDarker ].
	^ Color darkGray
]

{ #category : #'building' }
GT4AmigaRegisterDiagramElement >> tooltipForBit: aBit field: aFieldOrNil kind: aKind [
	| suffix |
	aFieldOrNil ifNil: [ ^ 'bit ' , aBit printString , ' (sin uso)' ].
	suffix := aKind caseOf: {
		[ #writable ] -> [ ' [clic para conmutar]' ].
		[ #transient ] -> [ ' [el copper del Workbench lo reescribe cada frame: la escritura no persiste]' ].
		[ #linkCritical ] -> [ ' [BLOQUEADO: escribirlo cortaria el enlace del monitor]' ].
		[ #systemCritical ] -> [ ' [BLOQUEADO: escribirlo dejaria una tarea en "task held"]' ].
		[ #readOnly ] -> [ ' [indicador de solo lectura]' ].
		[ #protocol ] -> [ ' [bit de protocolo, no estado]' ] }
		otherwise: [ '' ].
	^ aFieldOrNil name , ' (bit ' , aFieldOrNil bitsString , '): ' , aFieldOrNil description , suffix
]

{ #category : #'actions' }
GT4AmigaRegisterDiagramElement >> toggleField: aField [
	"Clicks never touch the machine directly: hand the toggle to the shared
	 gateway's write queue (serialized with the reads) and return. Only
	 #writable fields ever reach here."
	| reg |
	reg := register.
	register catalog observer enqueueWrite: [ reg toggleField: aField ]
]

{ #category : #'observing' }
GT4AmigaRegisterDiagramElement >> startObserving [
	"On entering the scene graph: listen for refreshes and ask the shared
	 gateway to keep my register fresh. No polling loop of my own."
	register catalog announcer unsubscribe: self.
	register catalog announcer weak when: GT4AmigaRegistersRefreshed send: #onRefreshed to: self.
	register catalog observer watch: self observationNeeds for: self
]

{ #category : #'observing' }
GT4AmigaRegisterDiagramElement >> stopObserving [
	"On leaving the scene graph: stop listening and drop my need from the
	 gateway (which idles when nothing is left to watch)."
	register catalog announcer unsubscribe: self.
	register catalog observer unwatch: self
]

{ #category : #'updating' }
GT4AmigaRegisterDiagramElement >> onRefreshed [
	"Announced from the gateway: hop to the UI thread to repaint."
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
				ifFalse: [ kind = #readOnly
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
