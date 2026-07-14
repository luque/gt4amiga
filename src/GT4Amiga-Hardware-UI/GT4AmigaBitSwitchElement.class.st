"
I am one switch of the hardware control panel: one bit field of a SET/CLR chip register, rendered as an LED dot with the field name under it.

My kind decides how I behave:
  #switch  clickable - a click queues an enable: or disable: of my field on the panel worker
  #led     read-only indicator (BBUSY, BZERO): the machine sets it, you only watch it
  #locked  a bit that WOULD be toggleable, but turning it off would cut the monitor link itself (INTEN, RBF, TBE, PORTS on INTENA) - shown with a red border and not clickable

I render ONLY the cached value of my register (project rule: no serial I/O on the UI thread). Clicks never talk to the machine directly: they hand a block to the panel queue, and the panel background worker performs the write, reads the value back through the read counterpart and announces, which repaints me.
"
Class {
	#name : #GT4AmigaBitSwitchElement,
	#superclass : #BlElement,
	#instVars : [
		'panel',
		'register',
		'field',
		'kind',
		'dot'
	],
	#category : #'GT4Amiga-Hardware-UI'
}

{ #category : #'instance creation' }
GT4AmigaBitSwitchElement >> setPanel: aControlPanel register: aRegister field: aField kind: aSymbol [
	panel := aControlPanel.
	register := aRegister.
	field := aField.
	kind := aSymbol.
	self buildSwitch.
	self updateFromCache
]

{ #category : #'building' }
GT4AmigaBitSwitchElement >> buildSwitch [
	self layout: BlLinearLayout vertical alignCenter.
	self constraintsDo: [ :c |
		c horizontal fitContent.
		c vertical fitContent ].
	self padding: (BlInsets all: 5).
	dot := BlElement new
		size: 16 @ 16;
		geometry: BlCircleGeometry new;
		border: (BlBorder paint: self borderColor width: self borderWidth);
		yourself.
	self addChild: dot.
	self addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement text: field name size: 9 color: Color darkGray);
		margin: (BlInsets top: 3);
		yourself).
	kind = #switch ifTrue: [
		self addEventHandlerOn: BlClickEvent do: [ :evt |
			evt consumed: true.
			self toggle ] ].
	self addAptitude: (BrGlamorousWithLabelTooltipAptitude text: self tooltipText)
]

{ #category : #'accessing' }
GT4AmigaBitSwitchElement >> borderColor [
	^ kind = #locked
		ifTrue: [ Color red ]
		ifFalse: [ Color darkGray ]
]

{ #category : #'accessing' }
GT4AmigaBitSwitchElement >> borderWidth [
	^ kind = #locked
		ifTrue: [ 3 ]
		ifFalse: [ 1 ]
]

{ #category : #'accessing' }
GT4AmigaBitSwitchElement >> tooltipText [
	| extra |
	extra := kind = #led
		ifTrue: [ ' [solo lectura]' ]
		ifFalse: [ kind = #locked
			ifTrue: [ ' [BLOQUEADO: apagarlo cortaria el enlace del monitor]' ]
			ifFalse: [ '' ] ].
	^ field name , ' (bit ' , field bitsString , '): ' , field description , extra
]

{ #category : #'testing' }
GT4AmigaBitSwitchElement >> isOn [
	^ register value
		ifNil: [ false ]
		ifNotNil: [ :v | (field valueIn: v) = 1 ]
]

{ #category : #'actions' }
GT4AmigaBitSwitchElement >> toggle [
	| reg fieldName turnOn |
	reg := register.
	fieldName := field name.
	turnOn := self isOn not.
	panel enqueue: [
		turnOn
			ifTrue: [ reg enable: fieldName ]
			ifFalse: [ reg disable: fieldName ] ]
]

{ #category : #'updating' }
GT4AmigaBitSwitchElement >> updateFromCache [
	dot background: (self isOn
		ifTrue: [ kind = #led
			ifTrue: [ Color orange ]
			ifFalse: [ Color green muchDarker ] ]
		ifFalse: [ Color veryDarkGray ])
]
