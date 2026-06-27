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
	| projectDir |
	vasmPath := self detectVasmPath.
	fsuaePath := '/usr/bin/fs-uae'.
	projectDir := self detectProjectDirectory.
	sharedDirectory := (projectDir / 'shared') asFileReference.
	kickstartPath := self detectKickstartIn: (projectDir / 'rom').
	workbenchHdfPath := self detectWorkbenchHdfIn: (projectDir / 'hdf').
	serialPort := 2345.
	amigaModel := 'A500'.
	chipMemory := 512.
	fastMemory := 0
]

{ #category : #initialization }
GT4AmigaConfiguration >> detectProjectDirectory [
	"Locate the gt4amiga project root. The Iceberg clone may live inside
	 pharo-local/iceberg/... so we walk up until we find a directory that
	 contains both src/ and lepiter/ (the true project root)."
	IceRepository registry
		detect: [ :r | r name = 'gt4amiga' ]
		ifFound: [ :r |
			| dir |
			dir := r repositoryDirectory.
			[ dir isRoot ] whileFalse: [
				((dir / 'src') exists and: [ (dir / 'lepiter') exists ])
					ifTrue: [ ^ dir ].
				dir := dir parent ].
			^ r repositoryDirectory ].
	^ FileLocator home / 'work' / 'gt4amiga'
]

{ #category : #initialization }
GT4AmigaConfiguration >> detectKickstartIn: aDirectory [
	"Return the first .rom file found in aDirectory, or nil."
	(aDirectory asFileReference exists) ifFalse: [ ^ nil ].
	aDirectory asFileReference children
		detect: [ :f | f extension asLowercase = 'rom' ]
		ifFound: [ :f | ^ f ]
		ifNone: [ ^ nil ]
]

{ #category : #initialization }
GT4AmigaConfiguration >> detectWorkbenchHdfIn: aDirectory [
	"Return the first .hdf file found in aDirectory, or nil."
	(aDirectory asFileReference exists) ifFalse: [ ^ nil ].
	aDirectory asFileReference children
		detect: [ :f | f extension asLowercase = 'hdf' ]
		ifFound: [ :f | ^ f ]
		ifNone: [ ^ nil ]
]

{ #category : #initialization }
GT4AmigaConfiguration >> detectVasmPath [
	"Try known locations for vasmm68k_mot; fall back to bare name (PATH lookup)."
	#('/home/osoco/local/vasm/vasmm68k_mot'
	  '/usr/local/bin/vasmm68k_mot'
	  '/usr/bin/vasmm68k_mot') do: [ :p |
		p asFileReference exists ifTrue: [ ^ p ] ].
	^ 'vasmm68k_mot'
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
