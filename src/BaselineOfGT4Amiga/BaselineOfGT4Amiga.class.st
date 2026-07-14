Class {
	#name : 'BaselineOfGT4Amiga',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfGT4Amiga',
	#package : 'BaselineOfGT4Amiga'
}

{ #category : 'lepiter' }
BaselineOfGT4Amiga class >> loadLepiter [
	IceRepository registry
		detect: [ :aRepository |
			aRepository name = 'gt4amiga' ]
		ifFound: [ :aRepository |
			| defaultDatabase props lepiterDir |
			lepiterDir := aRepository repositoryDirectory / 'lepiter'.
			defaultDatabase := LeDatabasesRegistry defaultLogicalDatabase.
			props := defaultDatabase properties.
			"Reset LeJsonV4 so the rebuilt reader includes GT4AmigaSnippet.
			 Then evict any stale GT4Amiga database from memory and reload fresh."
			LeJsonV4 cleanUniqueInstance.
			props registeredDatabaseDirectories:
				(props registeredDatabaseDirectories reject: [ :d | d = lepiterDir ]).
			defaultDatabase reload.
			props addRegisteredDirectory: lepiterDir.
			defaultDatabase reload ]
		ifNone: [
			self inform: 'Repository not found.' ]
]

{ #category : 'baseline' }
BaselineOfGT4Amiga >> baseline: spec [
	<baseline>
	spec
		for: #common
		do: [ spec
				package: 'GT4Amiga-Core';
				package: 'GT4Amiga-FSUAE' with: [ spec requires: #('GT4Amiga-Core') ];
				package: 'GT4Amiga-Bridge' with: [ spec requires: #('GT4Amiga-Core' 'GT4Amiga-FSUAE') ];
				package: 'GT4Amiga-Hardware' with: [ spec requires: #('GT4Amiga-Bridge') ];
					package: 'GT4Amiga-Hardware-UI' with: [ spec requires: #('GT4Amiga-Hardware') ];
				package: 'GT4Amiga-Lepiter'
					with: [ spec requires: #('GT4Amiga-Core' 'GT4Amiga-FSUAE') ];
				package: 'GT4Amiga-MCP'
					with: [ spec requires: #('GT4Amiga-Lepiter') ].
			spec postLoadDoIt: #registerGT4AmigaSnippets ]
]

{ #category : 'load hooks' }
BaselineOfGT4Amiga >> registerGT4AmigaSnippets [
	"Called by Metacello after all packages load.
	 Registers the custom Lepiter snippet type."
	(Smalltalk globals includesKey: #GT4AmigaSnippetRegistration)
		ifTrue: [ (Smalltalk globals at: #GT4AmigaSnippetRegistration) register ]
]
