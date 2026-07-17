"
The interactive control panel of the machine: the DMACON and INTENA register panels stacked, every writable bit a clickable switch. This is the first Bloc piece of the Interactive Hardware Reference, and it deliberately lives OUTSIDE GT4Amiga-Hardware, which stays a pure model layer.

Threading contract (project rule: no serial I/O on the UI thread):
- switch clicks only add a block to my queue (mutex-protected), and return immediately;
- ONE background worker drains the queue: it performs the write, re-reads DMACON and INTENA through their read counterparts and announces GT4AmigaRegistersRefreshed on the catalog announcer;
- while idle the worker polls those two registers every 2 seconds, so the panel also reflects changes made from anywhere else (a snippet, a program run through opcode X, the machine itself);
- the announcement handler repaints the switches from the cache via an enqueued Bloc task (UI thread), never from the worker;
- the worker starts when I enter the scene graph and stops (flag + unsubscribe) when I leave it, so closing the inspector leaves no orphan process behind.

Open me with: GT4AmigaControlPanelElement onCatalog: GT4AmigaChipRegisters default - or just inspect the catalog and pick the Control Panel view.
"
Class {
	#name : #GT4AmigaControlPanelElement,
	#superclass : #BlElement,
	#instVars : [
		'catalog',
		'queue',
		'mutex',
		'running',
		'generation',
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
	queue := OrderedCollection new.
	mutex := Mutex new.
	running := false.
	generation := 0.
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
	self addEventHandlerOn: BlElementAddedToSceneGraphEvent do: [ :evt | self startWorker ].
	self addEventHandlerOn: BlElementRemovedFromSceneGraphEvent do: [ :evt | self stopWorker ]
]

{ #category : #'accessing' }
GT4AmigaControlPanelElement >> isRunning [
	^ running
]

{ #category : #'worker' }
GT4AmigaControlPanelElement >> enqueue: aBlock [
	mutex critical: [ queue addLast: aBlock ]
]

{ #category : #'worker' }
GT4AmigaControlPanelElement >> startWorker [
	"The generation stamp retires a previous loop that survived a quick
	 detach/re-attach (inspector tabs, exporters) while blocked in serial
	 I/O - re-arming the shared running flag must not leave two loops."
	| myGeneration |
	running ifTrue: [ ^ self ].
	running := true.
	generation := generation + 1.
	myGeneration := generation.
	catalog announcer unsubscribe: self.
	catalog announcer when: GT4AmigaRegistersRefreshed send: #onRefreshed to: self.
	[ self workerLoopGeneration: myGeneration ]
		forkAt: Processor userBackgroundPriority
		named: 'GT4Amiga control panel worker'
]

{ #category : #'worker' }
GT4AmigaControlPanelElement >> stopWorker [
	running := false.
	catalog announcer unsubscribe: self
]

{ #category : #'worker' }
GT4AmigaControlPanelElement >> workerLoopGeneration: myGeneration [
	| idleMs |
	idleMs := 0.
	self pollRegisters.
	[ running and: [ generation = myGeneration ] ] whileTrue: [
		| action |
		action := mutex critical: [
			queue isEmpty
				ifTrue: [ nil ]
				ifFalse: [ queue removeFirst ] ].
		action
			ifNotNil: [
				[ action value ] on: Error do: [ :e | ].
				self pollRegisters.
				idleMs := 0 ]
			ifNil: [
				(Delay forMilliseconds: 200) wait.
				idleMs := idleMs + 200.
				idleMs >= 2000 ifTrue: [
					self pollRegisters.
					idleMs := 0 ] ] ]
]

{ #category : #'worker' }
GT4AmigaControlPanelElement >> pollRegisters [
	"Serial I/O - worker only. A dead link must not kill the loop."
	[ panels do: [ :p | p register read ].
	catalog announcer announce: GT4AmigaRegistersRefreshed new ]
		on: Error
		do: [ :e | ]
]

{ #category : #'updating' }
GT4AmigaControlPanelElement >> onRefreshed [
	"Announced from the worker: hop to the UI thread to repaint."
	self enqueueTask: (BlTaskAction new action: [ self updateFromCache ])
]

{ #category : #'updating' }
GT4AmigaControlPanelElement >> updateFromCache [
	panels do: [ :p | p updateFromCache ]
]
