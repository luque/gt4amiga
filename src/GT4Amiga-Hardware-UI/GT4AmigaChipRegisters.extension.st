Extension { #name : #GT4AmigaChipRegisters }

{ #category : #'*GT4Amiga-Hardware-UI' }
GT4AmigaChipRegisters >> gtControlPanelFor: aView [
	<gtView>
	^ aView explicit
		title: 'Control Panel';
		priority: 5.5;
		stencil: [ GT4AmigaControlPanelElement onCatalog: self ]
]
