Class {
	#name : #GT4AmigaSnippetElement,
	#superclass : #BrVerticalPane,
	#instVars : [
		'snippet'
		'codeEditor'
		'toolbar'
		'outputPane'
		'statusLabel'
	],
	#category : #'GT4Amiga-Lepiter'
}

{ #category : #initialization }
GT4AmigaSnippetElement >> initialize [
	super initialize.
	self matchParent.
	self padding: (BlInsets all: 4).
	self buildUI
]

{ #category : #accessing }
GT4AmigaSnippetElement >> snippet [
	^ snippet
]

{ #category : #accessing }
GT4AmigaSnippetElement >> snippet: aSnippet [
	snippet := aSnippet.
	codeEditor text: aSnippet code asRopedText.
	self updateOutputPane
]

{ #category : #'building - ui' }
GT4AmigaSnippetElement >> buildUI [
	self buildToolbar.
	self buildCodeEditor.
	self buildOutputPane
]

{ #category : #'building - ui' }
GT4AmigaSnippetElement >> buildToolbar [
	| assembleButton runButton platformLabel |
	toolbar := BrHorizontalPane new
		matchParent;
		vFitContent;
		padding: (BlInsets top: 2 bottom: 4);
		yourself.

	assembleButton := BrButton new
		aptitude: BrGlamorousButtonWithLabelAptitude;
		label: 'Assemble';
		action: [ self onAssemble ];
		yourself.

	runButton := BrButton new
		aptitude: BrGlamorousButtonWithLabelAptitude;
		label: 'Run on FS-UAE';
		action: [ self onAssembleAndRun ];
		yourself.

	statusLabel := BrLabel new
		aptitude: BrGlamorousLabelAptitude;
		text: '';
		yourself.

	toolbar
		addChild: assembleButton;
		addChild: runButton;
		addChild: statusLabel.

	self addChild: toolbar
]

{ #category : #'building - ui' }
GT4AmigaSnippetElement >> buildCodeEditor [
	codeEditor := BrCodeEditor new
		matchParent;
		height: 200;
		padding: (BlInsets all: 8);
		yourself.
	codeEditor styler: GT4Amiga68kStyler new.
	codeEditor
		when: BrTextEditorModifiedEvent
		do: [ :evt | snippet ifNotNil: [ snippet code: codeEditor text asString ] ].
	self addChild: codeEditor
]

{ #category : #'building - ui' }
GT4AmigaSnippetElement >> buildOutputPane [
	outputPane := BrVerticalPane new
		matchParent;
		vFitContent;
		yourself.
	self addChild: outputPane
]

{ #category : #actions }
GT4AmigaSnippetElement >> onAssemble [
	| result |
	statusLabel text: 'Assembling...' asRopedText.
	[ result := snippet assemble.
	  self showAssemblyResult: result ]
		on: Error
		do: [ :e | statusLabel text: ('Error: ' , e messageText) asRopedText ]
]

{ #category : #actions }
GT4AmigaSnippetElement >> onAssembleAndRun [
	| result output |
	statusLabel text: 'Assembling & running...' asRopedText.
	[ result := snippet assemble.
	  result success ifFalse: [
		  self showAssemblyResult: result. ^ self ].
	  statusLabel text: 'Running on FS-UAE...' asRopedText.
	  output := GT4FSUAERunner default run: result.
	  self showOutput: output.
	  statusLabel text: 'Done' asRopedText ]
		on: Error
		do: [ :e | statusLabel text: ('Error: ' , e messageText) asRopedText ]
]

{ #category : #'updating - ui' }
GT4AmigaSnippetElement >> showAssemblyResult: aResult [
	outputPane removeChildren.
	aResult success
		ifTrue: [
			statusLabel text: ('OK - ' , aResult binarySize printString , ' bytes') asRopedText.
			self showOutput: '' ]
		ifFalse: [
			statusLabel text: 'Assembly failed' asRopedText.
			self showOutput: aResult stderr ]
]

{ #category : #'updating - ui' }
GT4AmigaSnippetElement >> showOutput: aString [
	| outputLabel |
	outputPane removeChildren.
	aString isNil or: [ aString isEmpty ] ifTrue: [ ^ self ].
	outputLabel := BrLabel new
		aptitude: BrGlamorousMonospacedLabelAptitude;
		text: aString asRopedText;
		padding: (BlInsets all: 8);
		yourself.
	outputPane addChild: outputLabel
]

{ #category : #'updating - ui' }
GT4AmigaSnippetElement >> updateOutputPane [
	snippet ifNil: [ ^ self ].
	snippet lastResult ifNotNil: [ :r | self showAssemblyResult: r ]
]
