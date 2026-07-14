"
I am one physical chip of the Amiga: the 68000, Agnus, Denise, Paula or one of the two CIAs. I belong to a GT4AmigaMachine and I know which custom chip registers of its catalog live in me, exactly as the AHRM Appendix B register summary assigns them (its A/D/P chip column) - which is why DMACON appears in Agnus, Denise AND Paula (the write is broadcast to all three, each chip latches the enable bits of the DMA channels it drives), while DMACONR is answered by Agnus and Paula, and BPLCON0 is shared between Agnus (it needs HIRES/LACE for its counters) and Denise.

I resolve register names against the machine catalog lazily, so my registers ARE the live GT4AmigaChipRegister objects: inspecting a chip and drilling into a register gives the same live bit-field views as the catalog itself.
"
Class {
	#name : #GT4AmigaChip,
	#superclass : #Object,
	#instVars : [
		'machine',
		'name',
		'nickname',
		'description',
		'registerNames'
	],
	#category : #'GT4Amiga-Hardware'
}

{ #category : #'instance creation' }
GT4AmigaChip class >> machine: aMachine name: aName nickname: aNickname description: aString registerNames: aCollection [
	^ self new
		setMachine: aMachine
		name: aName
		nickname: aNickname
		description: aString
		registerNames: aCollection
]

{ #category : #'initialization' }
GT4AmigaChip >> setMachine: aMachine name: aName nickname: aNickname description: aString registerNames: aCollection [
	machine := aMachine.
	name := aName.
	nickname := aNickname.
	description := aString.
	registerNames := aCollection
]

{ #category : #'accessing' }
GT4AmigaChip >> name [
	^ name
]

{ #category : #'accessing' }
GT4AmigaChip >> nickname [
	^ nickname
]

{ #category : #'accessing' }
GT4AmigaChip >> description [
	^ description
]

{ #category : #'accessing' }
GT4AmigaChip >> registerNames [
	^ registerNames
]

{ #category : #'accessing' }
GT4AmigaChip >> registers [
	^ registerNames collect: [ :each | machine catalog at: each ]
]

{ #category : #'gt-extensions' }
GT4AmigaChip >> gtRegistersFor: aView [
	<gtView>
	registerNames isEmpty ifTrue: [ ^ aView empty ].
	^ aView columnedList
		title: 'Registers';
		priority: 5;
		items: [ self registers ];
		column: 'Name' text: [ :r | r name ] width: 80;
		column: 'Address' text: [ :r | r addressString ] width: 80;
		column: 'Mode' text: [ :r | r mode ] width: 70;
		column: 'Value' text: [ :r | r valueString ] width: 60;
		column: 'Description' text: [ :r | r description ];
		updateWhen: GT4AmigaRegistersRefreshed in: machine catalog announcer
]

{ #category : #'gt-extensions' }
GT4AmigaChip >> gtDetailsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Details';
		priority: 6;
		items: [ {
			{ 'Name'. name }.
			{ 'Chip'. nickname }.
			{ 'Registers'. registerNames size printString }.
			{ 'Description'. description } } ];
		column: 'Property' text: [ :pair | pair first ] width: 90;
		column: 'Value' text: [ :pair | pair second ]
]

{ #category : #'printing' }
GT4AmigaChip >> printOn: aStream [
	aStream nextPutAll: nickname
]
