Extension { #name : #GT4AmigaChipRegister }

{ #category : #'*GT4Amiga-Hardware-UI' }
GT4AmigaChipRegister >> gtDiagramFor: aView [
	<gtView>
	^ aView explicit
		title: 'Diagram';
		priority: 3;
		stencil: [ GT4AmigaRegisterDiagramElement onRegister: self ]
]
