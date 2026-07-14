"
I am one functional subsystem of the Amiga chipset - DMA, interrupts, Copper, playfield, color, beam, audio/disk. Where GT4AmigaChip slices the register catalog by PHYSICAL package (which silicon answers the address), I slice it by PURPOSE: the playfield subsystem gathers registers from both Agnus (fetch, modulos, window) and Denise (bitplane control, priority) because you program them together to put an image on screen.

Like a chip, I resolve register names against the machine catalog lazily, so drilling into me reaches the live register objects.
"
Class {
	#name : #GT4AmigaSubsystem,
	#superclass : #Object,
	#instVars : [
		'machine',
		'name',
		'description',
		'registerNames'
	],
	#category : #'GT4Amiga-Hardware'
}

{ #category : #'instance creation' }
GT4AmigaSubsystem class >> machine: aMachine name: aName description: aString registerNames: aCollection [
	^ self new
		setMachine: aMachine
		name: aName
		description: aString
		registerNames: aCollection
]

{ #category : #'initialization' }
GT4AmigaSubsystem >> setMachine: aMachine name: aName description: aString registerNames: aCollection [
	machine := aMachine.
	name := aName.
	description := aString.
	registerNames := aCollection
]

{ #category : #'accessing' }
GT4AmigaSubsystem >> name [
	^ name
]

{ #category : #'accessing' }
GT4AmigaSubsystem >> description [
	^ description
]

{ #category : #'accessing' }
GT4AmigaSubsystem >> registerNames [
	^ registerNames
]

{ #category : #'accessing' }
GT4AmigaSubsystem >> registers [
	^ registerNames collect: [ :each | machine catalog at: each ]
]

{ #category : #'accessing' }
GT4AmigaSubsystem >> chips [
	"The physical chips this subsystem spans (any chip owning at least
	 one of my registers)."
	^ machine chips select: [ :chip |
		chip registerNames anySatisfy: [ :each | registerNames includes: each ] ]
]

{ #category : #'gt-extensions' }
GT4AmigaSubsystem >> gtRegistersFor: aView [
	<gtView>
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

{ #category : #'printing' }
GT4AmigaSubsystem >> printOn: aStream [
	aStream
		nextPutAll: name;
		nextPutAll: ' (';
		print: registerNames size;
		nextPutAll: ' registers)'
]
