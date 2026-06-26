Class {
	#name : #GT4AmigaAssemblyResult,
	#superclass : #Object,
	#instVars : [
		'success'
		'outputFile'
		'stdout'
		'stderr'
		'exitCode'
		'sourceCode'
	],
	#category : #'GT4Amiga-Core'
}

{ #category : #accessing }
GT4AmigaAssemblyResult >> success [
	^ success
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> success: aBoolean [
	success := aBoolean
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> outputFile [
	^ outputFile
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> outputFile: aFileReference [
	outputFile := aFileReference
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> stdout [
	^ stdout
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> stdout: aString [
	stdout := aString
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> stderr [
	^ stderr
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> stderr: aString [
	stderr := aString
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> exitCode [
	^ exitCode
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> exitCode: anInteger [
	exitCode := anInteger
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> sourceCode [
	^ sourceCode
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> sourceCode: aString [
	sourceCode := aString
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> binary [
	"Read the assembled binary as a ByteArray"
	(outputFile isNil or: [ outputFile exists not ])
		ifTrue: [ ^ nil ].
	^ outputFile binaryReadStreamDo: [ :s | s contents ]
]

{ #category : #accessing }
GT4AmigaAssemblyResult >> binarySize [
	(outputFile isNil or: [ outputFile exists not ])
		ifTrue: [ ^ 0 ].
	^ outputFile size
]

{ #category : #testing }
GT4AmigaAssemblyResult >> hasErrors [
	^ success not
]

{ #category : #printing }
GT4AmigaAssemblyResult >> printOn: aStream [
	aStream nextPutAll: 'GT4AmigaAssemblyResult('.
	success
		ifTrue: [ aStream nextPutAll: 'OK, ' , self binarySize printString , ' bytes' ]
		ifFalse: [ aStream nextPutAll: 'FAILED' ].
	aStream nextPut: $)
]

{ #category : #'gt-extensions' }
GT4AmigaAssemblyResult >> gtViewStatusFor: aView [
	<gtView>
	^ aView text
		title: 'Status';
		priority: 5;
		text: [ self gtStatusText ]
]

{ #category : #private }
GT4AmigaAssemblyResult >> gtStatusText [
	| text |
	text := String streamContents: [ :s |
		s nextPutAll: (success ifTrue: [ 'Assembly SUCCESSFUL' ] ifFalse: [ 'Assembly FAILED' ]).
		s nextPut: Character lf.
		s nextPutAll: 'Exit code: ' , exitCode printString.
		s nextPut: Character lf.
		success ifTrue: [
			s nextPutAll: 'Output: ' , outputFile fullName.
			s nextPut: Character lf.
			s nextPutAll: 'Binary size: ' , self binarySize printString , ' bytes' ].
		stderr isNil not and: [ stderr isEmpty not ] ifTrue: [
			s nextPut: Character lf.
			s nextPutAll: '--- Assembler output ---'.
			s nextPut: Character lf.
			s nextPutAll: stderr ] ].
	^ text
]

{ #category : #'gt-extensions' }
GT4AmigaAssemblyResult >> gtViewSourceFor: aView [
	<gtView>
	sourceCode isNil ifTrue: [ ^ aView empty ].
	^ aView textEditor
		title: 'Source';
		priority: 10;
		text: [ sourceCode ]
]

{ #category : #'gt-extensions' }
GT4AmigaAssemblyResult >> gtViewErrorsFor: aView [
	<gtView>
	(stderr isNil or: [ stderr isEmpty ]) ifTrue: [ ^ aView empty ].
	^ aView text
		title: 'Errors';
		priority: 15;
		text: [ stderr ]
]
