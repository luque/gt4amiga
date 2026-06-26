Class {
	#name : #GT4AmigaConfiguration,
	#superclass : #Object,
	#instVars : [
		'vasmPath',
		'fsuaePath',
		'kickstartPath',
		'workbenchHdfPath',
		'sharedDirectory',
		'serialPort',
		'amigaModel',
		'chipMemory',
		'fastMemory'
	],
	#classVars : [ 'Default' ],
	#category : #'GT4Amiga-Core'
}

{ #category : #accessing }
GT4AmigaConfiguration class >> default [
	^ Default ifNil: [ Default := self new ]
]

{ #category : #accessing }
GT4AmigaConfiguration class >> default: aConfiguration [
	Default := aConfiguration
]

{ #category : #initialization }
GT4AmigaConfiguration >> initialize [
	vasmPath := '/usr/local/bin/vasmm68k_mot'.
	fsuaePath := '/usr/bin/fs-uae'.
	sharedDirectory := (FileLocator home / 'work' / 'gt4amiga' / 'shared') asFileReference.
	serialPort := 2345.
	amigaModel := 'A500'.
	chipMemory := 512.
	fastMemory := 0
]

{ #category : #accessing }
GT4AmigaConfiguration >> vasmPath [
	^ vasmPath
]

{ #category : #accessing }
GT4AmigaConfiguration >> vasmPath: aString [
	vasmPath := aString
]

{ #category : #accessing }
GT4AmigaConfiguration >> fsuaePath [
	^ fsuaePath
]

{ #category : #accessing }
GT4AmigaConfiguration >> fsuaePath: aString [
	fsuaePath := aString
]

{ #category : #accessing }
GT4AmigaConfiguration >> kickstartPath [
	^ kickstartPath
]

{ #category : #accessing }
GT4AmigaConfiguration >> kickstartPath: aFileReference [
	kickstartPath := aFileReference asFileReference
]

{ #category : #accessing }
GT4AmigaConfiguration >> workbenchHdfPath [
	^ workbenchHdfPath
]

{ #category : #accessing }
GT4AmigaConfiguration >> workbenchHdfPath: aFileReference [
	workbenchHdfPath := aFileReference asFileReference
]

{ #category : #accessing }
GT4AmigaConfiguration >> sharedDirectory [
	^ sharedDirectory
]

{ #category : #accessing }
GT4AmigaConfiguration >> sharedDirectory: aFileReference [
	sharedDirectory := aFileReference asFileReference
]

{ #category : #accessing }
GT4AmigaConfiguration >> serialPort [
	^ serialPort
]

{ #category : #accessing }
GT4AmigaConfiguration >> serialPort: anInteger [
	serialPort := anInteger
]

{ #category : #accessing }
GT4AmigaConfiguration >> amigaModel [
	^ amigaModel
]

{ #category : #accessing }
GT4AmigaConfiguration >> amigaModel: aString [
	amigaModel := aString
]

{ #category : #accessing }
GT4AmigaConfiguration >> chipMemory [
	^ chipMemory
]

{ #category : #accessing }
GT4AmigaConfiguration >> chipMemory: anInteger [
	chipMemory := anInteger
]

{ #category : #accessing }
GT4AmigaConfiguration >> fastMemory [
	^ fastMemory
]

{ #category : #accessing }
GT4AmigaConfiguration >> fastMemory: anInteger [
	fastMemory := anInteger
]

{ #category : #validation }
GT4AmigaConfiguration >> validate [
	"Returns a collection of validation error strings, empty if valid"
	| errors |
	errors := OrderedCollection new.
	vasmPath asFileReference exists
		ifFalse: [ errors add: 'vasm not found at: ' , vasmPath ].
	fsuaePath asFileReference exists
		ifFalse: [ errors add: 'fs-uae not found at: ' , fsuaePath ].
	kickstartPath isNil
		ifTrue: [ errors add: 'Kickstart ROM path not configured' ]
		ifFalse: [
			kickstartPath exists
				ifFalse: [ errors add: 'Kickstart ROM not found at: ' , kickstartPath fullName ] ].
	^ errors
]

{ #category : #'gt-extensions' }
GT4AmigaConfiguration >> gtViewDetailsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Configuration';
		priority: 5;
		items: [ self configurationPairs ];
		column: 'Setting' text: [ :pair | pair key ] width: 180;
		column: 'Value' text: [ :pair | pair value printString ]
]

{ #category : #private }
GT4AmigaConfiguration >> configurationPairs [
	^ {
		'vasm path' -> vasmPath.
		'fs-uae path' -> fsuaePath.
		'Kickstart ROM' -> (kickstartPath ifNil: [ 'not set' ] ifNotNil: [ :p | p fullName ]).
		'Workbench HDF' -> (workbenchHdfPath ifNil: [ 'not set' ] ifNotNil: [ :p | p fullName ]).
		'Shared directory' -> sharedDirectory fullName.
		'Serial port' -> serialPort.
		'Amiga model' -> amigaModel.
		'Chip RAM (KB)' -> chipMemory.
		'Fast RAM (KB)' -> fastMemory }
]
