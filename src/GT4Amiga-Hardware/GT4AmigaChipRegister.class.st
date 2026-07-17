"
I model one 16-bit custom chip register of the Amiga (the $DFFxxx register file), as an object that both REFLECTS and ACTS ON the real machine through the monitor.

My mode captures the AHRM access semantics:
  #read      readable at my own address (DMACONR, VPOSR, INTENAR...)
  #write     write-only; the hardware never answers a read
  #setClear  write-only with the bit-15 SET/CLR protocol (DMACON, INTENA, INTREQ, ADKCON): writing $8000+mask sets the masked bits, writing the bare mask clears them - never write a raw value
  #strobe    the act of writing is the operation (COPJMP1/2); the value is irrelevant

Most chip registers are write-only, so I know HOW my current value is knowable, in this order:
  1. derivation - a block that asks the OS for the truth (e.g. COLORxx registers read the Workbench ViewPort ColorMap via graphics GetRGB4, because the copper rewrites the hardware registers every frame and a raw readback is impossible)
  2. readOffset - my readable counterpart register (DMACON is knowable through DMACONR at $002; they are the same latch with two addresses)
  3. my own address, when mode is #read
  4. shadow - the last value written through me this session ('believed, not verified'), when nothing better exists.

IMPORTANT - no serial I/O on the UI thread (project rule): sending read or write runs protocol round-trips and must happen in a background process. Views only render my cached value; refresh me (or the whole GT4AmigaChipRegisters catalog) explicitly from a fork.

Writes: use write: for #write registers (updates the shadow), setBits: / clearBits: / enable: / disable: for #setClear registers (field names from the NDK includes, e.g. enable: over BPLEN of DMACON), and strobe for #strobe registers. Register accesses go over the R/W protocol commands, which are proper word-size accesses - never the byte-wise block transfer.
"
Class {
	#name : #GT4AmigaChipRegister,
	#superclass : #Object,
	#instVars : [
		'catalog',
		'name',
		'offset',
		'readOffset',
		'mode',
		'fields',
		'description',
		'shadow',
		'derivation',
		'cachedValue',
		'cachedAt'
	],
	#category : #'GT4Amiga-Hardware'
}

{ #category : #'write safety' }
GT4AmigaChipRegister class >> readOnlyIndicatorFieldsFor: aRegisterName [
	"Fields the hardware SETS and you only watch - writing them is
	 meaningless (the chip owns them). BBUSY/BZERO are the blitter's
	 status flags carried in DMACON's word."
	^ (aRegisterName = 'DMACON' or: [ aRegisterName = 'DMACONR' ])
		ifTrue: [ #('BBUSY' 'BZERO') ]
		ifFalse: [ #() ]
]

{ #category : #'write safety' }
GT4AmigaChipRegister class >> linkCriticalFieldsFor: aRegisterName [
	"Bits whose write would cut the monitor's own link. INTEN is the
	 master interrupt enable; RBF/TBE are the serial receive/transmit
	 interrupts the SER: monitor lives on; PORTS is CIA-A. UARTBRK forces
	 the serial line to a break condition - it silences the wire."
	aRegisterName = 'INTENA' ifTrue: [ ^ #('INTEN' 'RBF' 'TBE' 'PORTS') ].
	aRegisterName = 'ADKCON' ifTrue: [ ^ #('UARTBRK') ].
	^ #()
]

{ #category : #'write safety' }
GT4AmigaChipRegister class >> systemCriticalFieldsFor: aRegisterName [
	"Bits whose write would destabilize a running Workbench into a CPU
	 exception ('Software error - task held'), without necessarily
	 touching the monitor link. VERTB drives Intuition/Exec vertical-blank
	 housekeeping; EXTER is CIA-B (timer.device)."
	aRegisterName = 'INTENA' ifTrue: [ ^ #('VERTB' 'EXTER') ].
	^ #()
]

{ #category : #'write safety' }
GT4AmigaChipRegister class >> fullyLockedRegisters [
	"Registers where EVERY writable bit is unsafe under a running OS.
	 Writing INTREQ injects a live hardware interrupt straight into the
	 system - even a 'harmless-looking' bit can fire a handler that isn't
	 ready and hold a task."
	^ #('INTREQ')
]

{ #category : #'write safety' }
GT4AmigaChipRegister >> writeSafetyOf: aField [
	"Domain verdict on whether aField may be safely written from the
	 interactive figures, one of:
	  #protocol       the SETCLR command bit - carries no state
	  #readOnly       a read-mode/strobe register, or a hardware-set indicator
	  #linkCritical   writing it cuts the monitor's own link (locked)
	  #systemCritical writing it crashes/hangs the OS (locked)
	  #transient      writable, but the Workbench copper rewrites it every
	                  frame, so the write does not persist (COLORxx, BPLCONx,
	                  DDF/DIW, modulos - all derived from the live copper list)
	  #writable       safe to toggle and it latches (DMACON channels, the
	                  non-critical INTENA/ADKCON bits)"
	aField name = 'SETCLR' ifTrue: [ ^ #protocol ].
	(mode == #read or: [ mode == #strobe ]) ifTrue: [ ^ #readOnly ].
	((self class readOnlyIndicatorFieldsFor: name) includes: aField name)
		ifTrue: [ ^ #readOnly ].
	(self class fullyLockedRegisters includes: name) ifTrue: [ ^ #systemCritical ].
	((self class linkCriticalFieldsFor: name) includes: aField name)
		ifTrue: [ ^ #linkCritical ].
	((self class systemCriticalFieldsFor: name) includes: aField name)
		ifTrue: [ ^ #systemCritical ].
	(mode == #write and: [ derivation notNil ]) ifTrue: [ ^ #transient ].
	^ #writable
]

{ #category : #'write safety' }
GT4AmigaChipRegister >> isFieldWritable: aField [
	"Only a field the domain deems safe AND latching may be toggled from
	 the interactive figures. Transient (copper-owned) and locked bits are
	 rendered but never clickable."
	^ (self writeSafetyOf: aField) == #writable
]

{ #category : #'writing' }
GT4AmigaChipRegister >> toggleField: aField [
	"Flip aField's bit the way my mode demands: SET/CLR through the
	 protocol for #setClear registers, read-modify-write of the whole word
	 for a raw #write register. Serial I/O - never call on the UI thread."
	| current on |
	current := self value ifNil: [ 0 ].
	on := (aField valueIn: current) = 1.
	mode == #setClear ifTrue: [
		^ on
			ifTrue: [ self disable: aField name ]
			ifFalse: [ self enable: aField name ] ].
	^ self write: (on
		ifTrue: [ current bitAnd: (aField mask bitXor: 16rFFFF) ]
		ifFalse: [ current bitOr: aField mask ])
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> catalog [
	^ catalog
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> catalog: aCatalog [
	catalog := aCatalog
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> name [
	^ name
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> name: aString [
	name := aString
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> offset [
	^ offset
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> offset: anInteger [
	offset := anInteger
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> readOffset: anIntegerOrNil [
	readOffset := anIntegerOrNil
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> mode [
	^ mode
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> mode: aSymbol [
	mode := aSymbol
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> fields [
	^ fields
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> fields: aCollection [
	fields := aCollection
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> description [
	^ description
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> description: aString [
	description := aString
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> derivation: aBlock [
	"One-argument block (the catalog) answering my current value by
	 asking the OS, or nil when it cannot tell."
	derivation := aBlock
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> shadow [
	^ shadow
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> cachedAt [
	^ cachedAt
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> address [
	^ 16rDFF000 + offset
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> readAddress [
	^ 16rDFF000 + (readOffset ifNil: [ offset ])
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> addressString [
	^ '$' , (self address printPaddedWith: $0 to: 6 base: 16)
]

{ #category : #'testing' }
GT4AmigaChipRegister >> isReadable [
	"Can my REAL current value be obtained (as opposed to a shadow)?"
	^ derivation isNil not
		or: [ readOffset isNil not
		or: [ mode == #read ] ]
]

{ #category : #'reading' }
GT4AmigaChipRegister >> read [
	"Fetch my current value from the machine (serial I/O - never call
	 on the UI thread) and cache it. Falls back to the shadow when I am
	 not readable, and keeps the previous cache when the link answers
	 nothing."
	| v |
	self isReadable ifFalse: [ ^ shadow ].
	v := derivation
		ifNotNil: [ derivation value: catalog ]
		ifNil: [ catalog monitor readMemoryAt: self readAddress size: 2 ].
	v ifNil: [ ^ cachedValue ].
	cachedValue := v.
	cachedAt := DateAndTime now.
	^ v
]

{ #category : #'reading' }
GT4AmigaChipRegister >> value [
	"My best-known value WITHOUT touching the machine: the cache from
	 the last read, else the shadow of the last write, else nil. This is
	 what views render (no serial I/O on the UI thread)."
	^ cachedValue ifNil: [ shadow ]
]

{ #category : #'reading' }
GT4AmigaChipRegister >> valueString [
	^ self value
		ifNil: [ '?' ]
		ifNotNil: [ :v | '$' , (v printPaddedWith: $0 to: 4 base: 16) ]
]

{ #category : #'accessing' }
GT4AmigaChipRegister >> fieldNamed: aString [
	^ fields detect: [ :f | f name = aString ]
]

{ #category : #'writing' }
GT4AmigaChipRegister >> write: aValue [
	"Raw 16-bit write. For #setClear registers use setBits:/clearBits:
	 instead - a raw value would be misread as a SET/CLR command."
	mode == #read ifTrue: [ ^ self error: name , ' is read-only' ].
	mode == #setClear ifTrue: [
		^ self error: name , ' uses the SET/CLR protocol: use setBits:, clearBits:, enable: or disable:' ].
	mode == #write ifTrue: [ shadow := aValue ].
	^ catalog monitor writeMemoryAt: self address size: 2 value: aValue
]

{ #category : #'writing' }
GT4AmigaChipRegister >> setBits: aMask [
	"SET/CLR protocol: bit 15 on means 'set the other bits I carry'."
	mode == #setClear ifFalse: [ ^ self error: name , ' is not a SET/CLR register' ].
	^ catalog monitor
		writeMemoryAt: self address
		size: 2
		value: (16r8000 bitOr: (aMask bitAnd: 16r7FFF))
]

{ #category : #'writing' }
GT4AmigaChipRegister >> clearBits: aMask [
	"SET/CLR protocol: bit 15 off means 'clear the other bits I carry'."
	mode == #setClear ifFalse: [ ^ self error: name , ' is not a SET/CLR register' ].
	^ catalog monitor
		writeMemoryAt: self address
		size: 2
		value: (aMask bitAnd: 16r7FFF)
]

{ #category : #'writing' }
GT4AmigaChipRegister >> enable: aFieldName [
	"Set a named flag through the SET/CLR protocol, e.g. BPLEN on DMACON."
	^ self setBits: (self fieldNamed: aFieldName) mask
]

{ #category : #'writing' }
GT4AmigaChipRegister >> disable: aFieldName [
	^ self clearBits: (self fieldNamed: aFieldName) mask
]

{ #category : #'writing' }
GT4AmigaChipRegister >> strobe [
	"For #strobe registers the write itself is the operation."
	mode == #strobe ifFalse: [ ^ self error: name , ' is not a strobe register' ].
	^ catalog monitor writeMemoryAt: self address size: 2 value: 0
]

{ #category : #'printing' }
GT4AmigaChipRegister >> printOn: aStream [
	aStream
		nextPutAll: name;
		nextPutAll: ' (';
		nextPutAll: self addressString;
		nextPutAll: ', ';
		nextPutAll: mode printString;
		nextPutAll: ')'
]

{ #category : #'gt-extensions' }
GT4AmigaChipRegister >> gtBitsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Bits';
		priority: 4;
		items: [ fields ];
		column: 'Bits' text: [ :f | f bitsString ] width: 50;
		column: 'Field' text: [ :f | f name ] width: 100;
		column: 'Value'
			text: [ :f |
				self value
					ifNil: [ '?' ]
					ifNotNil: [ :v | (f valueIn: v) printString ] ]
			width: 55;
		column: 'Meaning' text: [ :f | f description ]
]

{ #category : #'gt-extensions' }
GT4AmigaChipRegister >> gtDetailsFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Register';
		priority: 6;
		items: [ {
			'Name' -> name.
			'Address' -> self addressString.
			'Mode' -> mode.
			'Value' -> self valueString.
			'Knowable via' -> (derivation isNil not
				ifTrue: [ 'derived from the OS' ]
				ifFalse: [ readOffset
					ifNotNil: [ :ro | 'read counterpart at $' , ((16rDFF000 + ro) printPaddedWith: $0 to: 6 base: 16) ]
					ifNil: [ mode == #read
						ifTrue: [ 'directly readable' ]
						ifFalse: [ 'shadow of last write only' ] ] ]).
			'Cached at' -> (cachedAt ifNil: [ 'never read' ]).
			'Description' -> description } ];
		column: 'Key' text: [ :pair | pair key ] width: 90;
		column: 'Value' text: [ :pair | pair value printString ]
]
