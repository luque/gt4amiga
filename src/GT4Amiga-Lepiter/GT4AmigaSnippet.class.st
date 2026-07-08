Class {
	#name : #GT4AmigaSnippet,
	#superclass : #LeSnippet,
	#instVars : [
		'code',
		'lastResult',
		'targetPlatform'
	],
	#category : #'GT4Amiga-Lepiter'
}

{ #category : #serialization }
GT4AmigaSnippet class >> leJsonV4Name [
	^ 'amiga68kSnippet'
]

{ #category : #serialization }
GT4AmigaSnippet class >> leJsonV4AttributeMapping [
	^ super leJsonV4AttributeMapping
		add: (#code -> #code);
		yourself
]

{ #category : #'instance creation' }
GT4AmigaSnippet class >> empty [
	^ self new
		code: '; 68000 Assembly
    rts
';
		yourself
]

{ #category : #'instance creation' }
GT4AmigaSnippet class >> typeName [
	^ 'amiga68k'
]

{ #category : #accessing }
GT4AmigaSnippet class >> description [
	^ 'Amiga 68k'
]

{ #category : #'gt-extensions' }
GT4AmigaSnippet class >> contextMenuItemSpecification [
	"This pragma is how LeContextMenuSnippetItemsCollector discovers snippet
	 types for the 'new snippet' menu - see its class comment. Without this
	 method GT4AmigaSnippet is invisible in that menu even though JSON
	 round-tripping and everything else about the type works fine."
	<leSnippetSpecification>
	^ LeContextMenuItemSpecification new
		snippetClass: self;
		title: self description
]

{ #category : #initialization }
GT4AmigaSnippet >> initialize [
	super initialize.
	code := ''.
	targetPlatform := #fsuae
]

{ #category : #accessing }
GT4AmigaSnippet >> code [
	^ code
]

{ #category : #accessing }
GT4AmigaSnippet >> code: aString [
	code := aString.
	self announceContentChanged
]

{ #category : #accessing }
GT4AmigaSnippet >> targetPlatform [
	^ targetPlatform
]

{ #category : #accessing }
GT4AmigaSnippet >> targetPlatform: aSymbol [
	"#fsuae or #a314"
	targetPlatform := aSymbol
]

{ #category : #accessing }
GT4AmigaSnippet >> lastResult [
	^ lastResult
]

{ #category : #actions }
GT4AmigaSnippet >> assemble [
	"Assemble the current code and return a GT4AmigaAssemblyResult."
	| assembler |
	assembler := GT4AmigaAssembler new.
	lastResult := assembler assemble: code.
	self announceContentChanged.
	^ lastResult
]

{ #category : #actions }
GT4AmigaSnippet >> assembleAndRun [
	"Assemble and run on the configured target platform."
	| result output |
	result := self assemble.
	result success ifFalse: [ ^ result ].
	output := targetPlatform = #fsuae
		ifTrue: [ GT4FSUAERunner default run: result ]
		ifFalse: [ 'Platform ' , targetPlatform , ' not yet supported' ].
	^ output
]

{ #category : #lepiter }
GT4AmigaSnippet >> acceptVisitor: aVisitor [
	^ aVisitor visitGT4AmigaSnippet: self
]

{ #category : #lepiter }
GT4AmigaSnippet >> contentAsString [
	^ code
]

{ #category : #lepiter }
GT4AmigaSnippet >> isEmpty [
	^ code isNil or: [ code isEmpty ]
]

{ #category : #lepiter }
GT4AmigaSnippet >> asSnippetViewModel [
	<return: #LeSnippetViewModel>
	^ GT4AmigaSnippetViewModel new snippetModel: self
]


{ #category : #serialization }
GT4AmigaSnippet >> jsonDictionary [
	^ super jsonDictionary
		at: 'code' put: code;
		yourself
]

{ #category : #serialization }
GT4AmigaSnippet >> updateFromJson: aJsonDictionary [
	super updateFromJson: aJsonDictionary.
	(aJsonDictionary includesKey: 'code')
		ifTrue: [ code := aJsonDictionary at: 'code' ]
]

{ #category : #'gt-extensions' }
GT4AmigaSnippet >> gtViewCodeFor: aView [
	<gtView>
	^ aView textEditor
		title: 'Code';
		priority: 5;
		text: [ code asRopedText ]
]

{ #category : #'gt-extensions' }
GT4AmigaSnippet >> gtActionAssembleFor: anAction [
	<gtAction>
	^ anAction button
		label: 'Assemble';
		action: [ self assemble ]
]

{ #category : #'gt-extensions' }
GT4AmigaSnippet >> gtActionRunFor: anAction [
	<gtAction>
	^ anAction button
		label: 'Run on FS-UAE';
		action: [ self assembleAndRun ]
]
