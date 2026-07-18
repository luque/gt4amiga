"
The interactive control panel of the machine: the DMACON and INTENA register panels stacked, every writable bit a clickable switch. This is the first Bloc piece of the Interactive Hardware Reference, and it deliberately lives OUTSIDE GT4Amiga-Hardware, which stays a pure model layer.

Threading contract (project rule: no serial I/O on the UI thread): I run NO polling loop of my own. On entering the scene graph I subscribe to the catalog's shared serial gateway (GT4AmigaChipRegisters>>observer) declaring my observationNeeds - DMACON and INTENA; the gateway keeps them fresh for every view with a single de-duplicated reader and announces GT4AmigaRegistersRefreshed, which repaints the switches from the cache on the UI thread. A switch click hands its SET/CLR write to the gateway's write queue (my enqueue: forwards to the gateway), serialized with the reads - never on the UI thread. On leaving the scene graph I unwatch.

Open me with: GT4AmigaControlPanelElement onCatalog: GT4AmigaChipRegisters default - or just inspect the catalog and pick the Control Panel view.
"
Class {
	#name : #GT4AmigaControlPanelElement,
	#superclass : #BlElement,
	#instVars : [
		'catalog',
		'panels'
	],
	#category : #'GT4Amiga-Hardware-UI'
}

{ #category : #'instance creation' }
GT4AmigaControlPanelElement class >> onCatalog: aCatalog [
	^ self new setCatalog: aCatalog
]

{ #category : #'text' }
GT4AmigaControlPanelElement class >> text: aString size: aSize color: aColor [
	| t |
	t := aString asRopedText.
	t glamorousRegularFont; fontSize: aSize; foreground: aColor.
	^ t
]

{ #category : #'instance creation' }
GT4AmigaControlPanelElement >> setCatalog: aCatalog [
	catalog := aCatalog.
	self layout: BlLinearLayout vertical.
	self constraintsDo: [ :c |
		c horizontal matchParent.
		c vertical fitContent ].
	self padding: (BlInsets all: 6).
	panels := #('DMACON' 'INTENA') collect: [ :n |
		GT4AmigaRegisterPanelElement new
			setPanel: self
			register: (catalog at: n);
			yourself ].
	panels do: [ :p | self addChild: p ].
	self addEventHandlerOn: BlElementAddedToSceneGraphEvent do: [ :evt | self startObserving ].
	self addEventHandlerOn: BlElementRemovedFromSceneGraphEvent do: [ :evt | self stopObserving ]
]

{ #category : #'accessing' }
GT4AmigaControlPanelElement >> observationNeeds [
	"What the shared gateway must keep fresh for me: my panels' registers."
	^ panels collect: [ :p | p register ]
]

{ #category : #'testing' }
GT4AmigaControlPanelElement >> isObserving [
	^ catalog observer isWatching: self
]

{ #category : #'worker' }
GT4AmigaControlPanelElement >> enqueue: aBlock [
	"A switch click routes its SET/CLR write here; forward it to the shared
	 gateway, serialized with the reads (never on the UI thread)."
	catalog observer enqueueWrite: aBlock
]

{ #category : #'observing' }
GT4AmigaControlPanelElement >> startObserving [
	catalog announcer unsubscribe: self.
	catalog announcer weak when: GT4AmigaRegistersRefreshed send: #onRefreshed to: self.
	catalog observer watch: self observationNeeds for: self
]

{ #category : #'observing' }
GT4AmigaControlPanelElement >> stopObserving [
	catalog announcer unsubscribe: self.
	catalog observer unwatch: self
]

{ #category : #'updating' }
GT4AmigaControlPanelElement >> onRefreshed [
	"Announced from the gateway: hop to the UI thread to repaint."
	self enqueueTask: (BlTaskAction new action: [ self updateFromCache ])
]

{ #category : #'updating' }
GT4AmigaControlPanelElement >> updateFromCache [
	panels do: [ :p | p updateFromCache ]
]
