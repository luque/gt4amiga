Class {
	#name : 'BaselineOfGT4Amiga',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfGT4Amiga',
	#package : 'BaselineOfGT4Amiga'
}

{ #category : 'baseline' }
BaselineOfGT4Amiga >> baseline: spec [
	<baseline>
	spec
		for: #common
		do: [ spec
				package: 'GT4Amiga-Core';
				package: 'GT4Amiga-FSUAE' with: [ spec requires: #('GT4Amiga-Core') ];
				package: 'GT4Amiga-Lepiter'
					with: [ spec requires: #('GT4Amiga-Core' 'GT4Amiga-FSUAE') ].
			spec postLoadDoIt: #registerGT4AmigaSnippets ]
]

{ #category : 'load hooks' }
BaselineOfGT4Amiga >> registerGT4AmigaSnippets [
	"Called by Metacello after all packages load.
	 Registers the custom Lepiter snippet type."
	(Smalltalk globals includesKey: #GT4AmigaSnippetRegistration)
		ifTrue: [ (Smalltalk globals at: #GT4AmigaSnippetRegistration) register ]
]
