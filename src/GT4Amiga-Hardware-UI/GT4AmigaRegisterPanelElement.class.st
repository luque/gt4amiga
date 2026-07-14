"
The control panel of ONE SET/CLR chip register: a header with the register name, address and current hex value, and a wrapping row of GT4AmigaBitSwitchElement, one per bit field (SETCLR itself is protocol, not state, so it is not shown; fields are laid out MSB first, matching the AHRM tables).

Which fields are read-only indicators or locked is static per-register knowledge on my class side: DMACON shows BBUSY and BZERO as LEDs (the blitter sets them, nobody toggles them), and INTENA locks INTEN, RBF, TBE and PORTS because the monitor itself lives on the serial interrupts - turning those off from the panel would saw off the branch we are sitting on.

I never do serial I/O: I paint the register cache and delegate every action to the GT4AmigaControlPanelElement worker through its queue.
"
Class {
	#name : #GT4AmigaRegisterPanelElement,
	#superclass : #BlElement,
	#instVars : [
		'panel',
		'register',
		'valueLabel',
		'switches'
	],
	#category : #'GT4Amiga-Hardware-UI'
}

{ #category : #'configuration' }
GT4AmigaRegisterPanelElement class >> readOnlyFieldsFor: aRegisterName [
	^ aRegisterName = 'DMACON'
		ifTrue: [ #('BBUSY' 'BZERO') ]
		ifFalse: [ #() ]
]

{ #category : #'configuration' }
GT4AmigaRegisterPanelElement class >> lockedFieldsFor: aRegisterName [
	^ aRegisterName = 'INTENA'
		ifTrue: [ #('INTEN' 'RBF' 'TBE' 'PORTS') ]
		ifFalse: [ #() ]
]

{ #category : #'accessing' }
GT4AmigaRegisterPanelElement >> register [
	^ register
]

{ #category : #'instance creation' }
GT4AmigaRegisterPanelElement >> setPanel: aControlPanel register: aRegister [
	panel := aControlPanel.
	register := aRegister.
	self buildPanel.
	self updateFromCache
]

{ #category : #'building' }
GT4AmigaRegisterPanelElement >> buildPanel [
	| header row |
	self layout: BlLinearLayout vertical.
	self constraintsDo: [ :c |
		c horizontal matchParent.
		c vertical fitContent ].
	self padding: (BlInsets all: 8).
	self margin: (BlInsets all: 4).
	self border: (BlBorder paint: Color darkGray width: 1).
	header := BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical fitContent ];
		yourself.
	header addChild: (BlTextElement new
		text: (GT4AmigaControlPanelElement
			text: register name , '  ' , register addressString , '   '
			size: 13
			color: Color black);
		yourself).
	valueLabel := BlTextElement new.
	header addChild: valueLabel.
	row := BlElement new
		layout: BlFlowLayout horizontal;
		constraintsDo: [ :c |
			c horizontal matchParent.
			c vertical fitContent ];
		margin: (BlInsets top: 6);
		yourself.
	switches := (register fields reject: [ :f | f name = 'SETCLR' ]) collect: [ :f |
		GT4AmigaBitSwitchElement new
			setPanel: panel
			register: register
			field: f
			kind: (self kindFor: f);
			yourself ].
	switches do: [ :s | row addChild: s ].
	self addChild: header.
	self addChild: row
]

{ #category : #'building' }
GT4AmigaRegisterPanelElement >> kindFor: aField [
	((self class readOnlyFieldsFor: register name) includes: aField name)
		ifTrue: [ ^ #led ].
	((self class lockedFieldsFor: register name) includes: aField name)
		ifTrue: [ ^ #locked ].
	^ #switch
]

{ #category : #'updating' }
GT4AmigaRegisterPanelElement >> updateFromCache [
	valueLabel text: (GT4AmigaControlPanelElement
		text: register valueString
		size: 13
		color: Color blue muchDarker).
	switches do: [ :s | s updateFromCache ]
]
