"
I describe one named bit field inside a custom chip register: a name (the AHRM/include mnemonic, e.g. DMAEN or BPU), the bit range I occupy (msb..lsb, a single bit when they are equal), and what I mean. I am pure data plus extraction logic - I do not talk to the Amiga; my owning GT4AmigaChipRegister does. Bit numbers come from the canonical NDK includes (hardware/dmabits.i, intbits.i, adkbits.i) and the Amiga Hardware Reference Manual register appendix.
"
Class {
	#name : #GT4AmigaBitField,
	#superclass : #Object,
	#instVars : [
		'name',
		'msb',
		'lsb',
		'description'
	],
	#category : #'GT4Amiga-Hardware'
}

{ #category : #'accessing' }
GT4AmigaBitField >> name [
	^ name
]

{ #category : #'accessing' }
GT4AmigaBitField >> name: aString [
	name := aString
]

{ #category : #'accessing' }
GT4AmigaBitField >> msb [
	^ msb
]

{ #category : #'accessing' }
GT4AmigaBitField >> msb: anInteger [
	msb := anInteger
]

{ #category : #'accessing' }
GT4AmigaBitField >> lsb [
	^ lsb
]

{ #category : #'accessing' }
GT4AmigaBitField >> lsb: anInteger [
	lsb := anInteger
]

{ #category : #'accessing' }
GT4AmigaBitField >> description [
	^ description
]

{ #category : #'accessing' }
GT4AmigaBitField >> description: aString [
	description := aString
]

{ #category : #'testing' }
GT4AmigaBitField >> isFlag [
	"A single-bit field: on or off."
	^ msb = lsb
]

{ #category : #'extracting' }
GT4AmigaBitField >> width [
	^ msb - lsb + 1
]

{ #category : #'extracting' }
GT4AmigaBitField >> mask [
	"The field's bits, in place within the 16-bit register word."
	^ ((1 bitShift: self width) - 1) bitShift: lsb
]

{ #category : #'extracting' }
GT4AmigaBitField >> valueIn: aWord [
	"Extract my (right-justified) value from a full register word."
	^ (aWord bitShift: lsb negated) bitAnd: (1 bitShift: self width) - 1
]

{ #category : #'printing' }
GT4AmigaBitField >> bitsString [
	^ self isFlag
		ifTrue: [ msb printString ]
		ifFalse: [ msb printString , '-' , lsb printString ]
]

{ #category : #'printing' }
GT4AmigaBitField >> printOn: aStream [
	aStream
		nextPutAll: name;
		nextPutAll: ' (bit';
		nextPutAll: (self isFlag ifTrue: [ ' ' ] ifFalse: [ 's ' ]);
		nextPutAll: self bitsString;
		nextPutAll: ')'
]

{ #category : #'gt-extensions' }
GT4AmigaBitField >> gtDetailsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Field';
		priority: 5;
		items: [ {
			'Name' -> name.
			'Bits' -> self bitsString.
			'Width' -> self width.
			'Mask' -> ('$' , (self mask printPaddedWith: $0 to: 4 base: 16)).
			'Meaning' -> description } ];
		column: 'Key' text: [ :pair | pair key ] width: 80;
		column: 'Value' text: [ :pair | pair value printString ]
]
