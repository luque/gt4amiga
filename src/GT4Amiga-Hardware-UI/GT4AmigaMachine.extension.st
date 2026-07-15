Extension { #name : #GT4AmigaMachine }

{ #category : #'*GT4Amiga-Hardware-UI' }
GT4AmigaMachine >> gtDiagramFor: aView [
	<gtView>
	^ aView explicit
		title: 'Block diagram';
		priority: 3;
		stencil: [ GT4AmigaBlockDiagramElement onMachine: self ]
]

{ #category : #'*GT4Amiga-Hardware-UI' }
GT4AmigaMachine >> gtDmaTimelineFor: aView [
	<gtView>
	^ aView explicit
		title: 'DMA timeline';
		priority: 4;
		stencil: [ GT4AmigaDMATimelineElement onMachine: self ]
]
