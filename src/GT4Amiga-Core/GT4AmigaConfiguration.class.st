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
		'monitorHost',
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
	"Locate the gt4amiga project root. The Iceberg clone (pharo-local/iceberg/...)
	 is itself a full git clone of the same repo, so it has the identical src/ +
	 lepiter/ layout - that check alone can't tell it apart from the true project
	 root and would stop climbing right at the clone. Require an actual .rom file
	 under rom/ too: ROMs are gitignored (only .gitkeep/.gitignore are committed),
	 so they only ever exist in the real working checkout, never in Iceberg's clone."
	IceRepository registry
		detect: [ :r | r name = 'gt4amiga' ]
		ifFound: [ :r |
			| dir |
			"resolve: repositoryDirectory is a FileLocator whose parent chain
			 breaks once it climbs past a segment literally named 'iceberg'
			 (collides with a registered {gtResource} locator scheme) - resolve
			 to a plain absolute FileReference first to sidestep that."
			dir := r repositoryDirectory resolve.
			[ dir isRoot ] whileFalse: [
				((dir / 'src') exists
					and: [ (dir / 'lepiter') exists
					and: [ (self detectKickstartIn: (dir / 'rom')) isNotNil ] ])
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
GT4AmigaConfiguration >> monitorHost [
	"Host donde escucha el monitor. Por defecto 127.0.0.1 (FS-UAE puentea
	 el SER: emulado a un socket TCP local). Para hardware real (p.ej.
	 A500 + PiStorm con el monitor en modo bsdsocket) poner aqui la IP
	 del Amiga en la red local:
	   GT4AmigaConfiguration default monitorHost: '192.168.1.x'"
	^ monitorHost ifNil: [ '127.0.0.1' ]
]

{ #category : #accessing }
GT4AmigaConfiguration >> monitorHost: aString [
	monitorHost := aString
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
