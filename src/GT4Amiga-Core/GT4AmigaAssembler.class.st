Class {
	#name : #GT4AmigaAssembler,
	#superclass : #Object,
	#instVars : [ 'configuration' ],
	#category : #'GT4Amiga-Core'
}

{ #category : #'instance creation' }
GT4AmigaAssembler class >> new [
	^ super new initialize
]

{ #category : #'instance creation' }
GT4AmigaAssembler class >> withConfiguration: aConfiguration [
	^ self new
		configuration: aConfiguration;
		yourself
]

{ #category : #initialization }
GT4AmigaAssembler >> initialize [
	configuration := GT4AmigaConfiguration default
]

{ #category : #accessing }
GT4AmigaAssembler >> configuration [
	^ configuration
]

{ #category : #accessing }
GT4AmigaAssembler >> configuration: aConfiguration [
	configuration := aConfiguration
]

{ #category : #assembling }
GT4AmigaAssembler >> assemble: sourceString [
	"Assemble 68000 source code into an AmigaOS hunk-format executable.
	 Returns a GT4AmigaAssemblyResult."
	^ self assemble: sourceString format: #hunk
]

{ #category : #assembling }
GT4AmigaAssembler >> assemble: sourceString format: aSymbol [
	"Assemble 68000 source code. aSymbol can be #hunk (AmigaOS executable) or #bin (flat binary).
	 Returns a GT4AmigaAssemblyResult."
	| workDir sourceFile outputFile formatFlag result proc |

	workDir := FileLocator temp / 'gt4amiga'.
	workDir ensureCreateDirectory.
	sourceFile := workDir / 'source.s'.
	outputFile := workDir / 'program'.
	sourceFile exists ifTrue: [ sourceFile delete ].
	outputFile exists ifTrue: [ outputFile delete ].

	sourceFile writeStreamDo: [ :s | s nextPutAll: sourceString ].

	formatFlag := aSymbol = #bin ifTrue: [ '-Fbin' ] ifFalse: [ '-Fhunk' ].

	proc := GtSubprocessWithInMemoryOutput new
		command: configuration vasmPath;
		arguments: {
			'-m68000'.
			formatFlag.
			'-spaces'.
			'-o'. outputFile fullName.
			sourceFile fullName };
		runAndWait.

	result := GT4AmigaAssemblyResult new.
	result exitCode: proc exitCode.
	result stdout: proc stdout.
	result stderr: proc stderr.
	result sourceCode: sourceString.

	result success: (proc exitCode = 0 and: [ outputFile exists ]).
	result success ifTrue: [ result outputFile: outputFile ].

	^ result
]

{ #category : #assembling }
GT4AmigaAssembler >> assembleFile: aFileReference [
	"Assemble from a .s file. Returns a GT4AmigaAssemblyResult."
	| source |
	source := aFileReference readStreamDo: [ :s | s contents ].
	^ self assemble: source
]

{ #category : #'gt-extensions' }
GT4AmigaAssembler >> gtViewAssembleFor: aView [
	<gtView>
	^ aView textEditor
		title: 'Assemble';
		priority: 5;
		text: [ '; Write 68000 assembly here
; Example:
    move.l  #$DFF000, a0   ; Custom chip base
    move.w  #$0F00, $180(a0) ; COLOR00 = red
.loop:
    bra     .loop
' ]
]
