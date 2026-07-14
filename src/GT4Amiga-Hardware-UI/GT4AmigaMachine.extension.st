Extension { #name : #GT4AmigaMachine }

{ #category : #'*GT4Amiga-Hardware-UI' }
GT4AmigaMachine >> gtDiagramFor: aView [
	<gtView>
	^ aView explicit
		title: 'Block diagram';
		priority: 3;
		stencil: [ GT4AmigaBlockDiagramElement onMachine: self ]
]
