Class {
	#name : #GT4AmigaSnippetElement,
	#superclass : #LeSnippetElement,
	#instVars : [
		'codeEditor',
		'toolbar',
		'outputPane',
		'statusLabel'
	],
	#category : #'GT4Amiga-Lepiter'
}

{ #category : #initialization }
GT4AmigaSnippetElement >> initialize [
	super initialize.
	self buildContentArea
]

{ #category : #'api - snippet' }
GT4AmigaSnippetElement >> snippetContent [
	<return: #BlElement>
	^ toolbar
]

{ #category : #'api - snippet' }
GT4AmigaSnippetElement >> snippetToolbar [
	<return: #BlElement or: nil>
	^ nil
]

{ #category : #'api - snippet' }
GT4AmigaSnippetElement >> onSnippetViewModelChanged [
	super onSnippetViewModelChanged.
	codeEditor text: self snippetViewModel snippetModel code asRopedText.
	self updateOutputPane
]

{ #category : #'building - ui' }
GT4AmigaSnippetElement >> buildContentArea [
	| buttonBar assembleButton runButton |

	codeEditor := BrEditor new
		aptitude: BrGlamorousCodeEditorAptitude new;
		constraintsDo: [ :c | c horizontal matchParent. c vertical exact: 200 ];
		padding: (BlInsets all: 6);
		yourself.
	codeEditor
		when: BrTextEditorModifiedEvent
		do: [ :evt | self onEditorTextChanged ].

	statusLabel := BrLabel new
		aptitude: BrGlamorousLabelAptitude;
		text: '' asRopedText;
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

	buttonBar := BlElement new
		layout: BlLinearLayout horizontal;
		constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ];
		padding: (BlInsets top: 2 bottom: 4);
		addChildren: { assembleButton. runButton. statusLabel };
		yourself.

	outputPane := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ];
		yourself.

	toolbar := BlElement new
		layout: BlLinearLayout vertical;
		constraintsDo: [ :c | c horizontal matchParent. c vertical fitContent ];
		addChildren: { codeEditor. buttonBar. outputPane };
		yourself
]

{ #category : #private }
GT4AmigaSnippetElement >> onEditorTextChanged [
	| newCode s |
	self hasSnippetViewModel ifFalse: [ ^ self ].
	s := self snippetViewModel snippetModel.
	newCode := codeEditor text asString.
	newCode = s code ifFalse: [ s code: newCode ]
]

{ #category : #actions }
GT4AmigaSnippetElement >> onAssemble [
	| result |
	statusLabel text: 'Assembling...' asRopedText.
	[ result := self snippetViewModel snippetModel assemble.
	  self showAssemblyResult: result ]
		on: Error
		do: [ :e | statusLabel text: ('Error: ' , e messageText) asRopedText ]
]

{ #category : #actions }
GT4AmigaSnippetElement >> onAssembleAndRun [
	| result output |
	statusLabel text: 'Assembling & running...' asRopedText.
	[ result := self snippetViewModel snippetModel assemble.
	  result success ifFalse: [
		  self showAssemblyResult: result. ^ self ].
	  statusLabel text: 'Running on FS-UAE...' asRopedText.
	  output := GT4FSUAERunner default run: result.
	  self showOutput: output.
	  statusLabel text: 'Done.' asRopedText ]
		on: Error
		do: [ :e | statusLabel text: ('Error: ' , e messageText) asRopedText ]
]

{ #category : #'updating - ui' }
GT4AmigaSnippetElement >> showAssemblyResult: aResult [
	aResult success
		ifTrue: [
			statusLabel text:
				('OK — ' , aResult binarySize printString , ' bytes') asRopedText.
			self showOutput: '' ]
		ifFalse: [
			statusLabel text: 'Assembly failed' asRopedText.
			self showOutput: aResult stderr ]
]

{ #category : #'updating - ui' }
GT4AmigaSnippetElement >> showOutput: aString [
	| outputLabel |
	outputPane removeChildren.
	(aString isNil or: [ aString isEmpty ]) ifTrue: [ ^ self ].
	outputLabel := BrLabel new
		aptitude: BrGlamorousLabelAptitude new;
		text: aString asRopedText;
		padding: (BlInsets all: 8);
		yourself.
	outputPane addChild: outputLabel
]

{ #category : #'updating - ui' }
GT4AmigaSnippetElement >> updateOutputPane [
	self hasSnippetViewModel ifFalse: [ ^ self ].
	self snippetViewModel snippetModel lastResult
		ifNotNil: [ :r | self showAssemblyResult: r ]
]
