"
I am the single serial gateway of the live hardware model: the ONE background process that reads chip state from the machine, so that no two readers ever hit the monitor's single socket at once (concurrent readers were the cause of the serial-link jams that plagued the per-view workers).

Views do not poll. They declare WHAT they need kept fresh and subscribe to the announcement; I do the I/O for everyone:

  observer watch: { register. anotherRegister } for: aView.   (aView needs these fresh while visible)
  observer unwatch: aView.                                     (aView left the scene graph / page closed)
  observer enqueueWrite: [ reg disable: 'BPLEN' ].             (a toggle, serialized with the reads)

While anything is watched (or a write is queued) I run one loop that: drains queued writes, then re-reads the UNION of all watched registers ONCE (so DMACON is read a single time even if five views show it), and announces GT4AmigaRegistersRefreshed on the catalog's announcer. Every subscribed view repaints from the register CACHE on the UI thread - no serial I/O on the UI thread. When the last subscriber leaves and no write is pending, the loop stops; a new watch/write restarts it. A generation stamp retires a loop left over from a quick stop/restart while it was blocked in a serial read, without terminating it mid-frame-exchange.

Leak backstop (two weak references, both required): I hold subscribers WEAKLY (WeakIdentityKeyDictionary), AND views subscribe to the catalog announcer WEAKLY (announcer weak when:send:to:). Those are the only two references that could otherwise pin a view: with both weak, a view ever dropped WITHOUT its explicit unwatch - say a virtualized Lepiter page snippet whose scene-graph removal never fired - is garbage-collected, its watch entry and its announcer subscription both fall away on finalization/next announce, and the loop idles once nothing live remains. No unbounded leak. The explicit unwatch on scene-graph leave stays the primary, immediate teardown; the weak refs are only the safety net. Finalization compacts the registry on its own process, outside my mutex, so the loop body tolerates a transient race by skipping a tick.

This is the coordination layer the roadmap calls for. Two ways to feed me:
  - OUTSIDE a Lepiter page (inspector, Miller column, standalone): each view subscribes itself on scene-graph enter/leave.
  - INSIDE a Lepiter page: a page-level observer aggregates the page's live views into one grouped subscription with its own lifecycle and controls (pause/resume/step/cadence), and registers that group with me.
Either way the serial I/O stays unified here, so page and non-page views never contend for the socket.
"
Class {
	#name : #GT4AmigaHardwareObserver,
	#superclass : #Object,
	#instVars : [
		'catalog',
		'watch',
		'writeQueue',
		'mutex',
		'running',
		'generation',
		'refreshRequested',
		'cadenceMs'
	],
	#category : #'GT4Amiga-Hardware'
}

{ #category : #'instance creation' }
GT4AmigaHardwareObserver class >> on: aCatalog [
	^ self new setCatalog: aCatalog
]

{ #category : #'instance creation' }
GT4AmigaHardwareObserver >> setCatalog: aCatalog [
	catalog := aCatalog.
	watch := WeakIdentityKeyDictionary new.
	writeQueue := OrderedCollection new.
	mutex := Mutex new.
	running := false.
	generation := 0.
	refreshRequested := false.
	cadenceMs := 2000
]

{ #category : #'accessing' }
GT4AmigaHardwareObserver >> catalog [
	^ catalog
]

{ #category : #'accessing' }
GT4AmigaHardwareObserver >> cadenceMs [
	^ cadenceMs
]

{ #category : #'accessing' }
GT4AmigaHardwareObserver >> cadenceMs: anInteger [
	"The idle poll interval in milliseconds. A page can slow this down or
	 speed it up for its own live demo without affecting the I/O being
	 shared and serialized here."
	cadenceMs := anInteger
]

{ #category : #'testing' }
GT4AmigaHardwareObserver >> isRunning [
	^ running
]

{ #category : #'testing' }
GT4AmigaHardwareObserver >> isWatching: aSubscriber [
	^ mutex critical: [ watch includesKey: aSubscriber ]
]

{ #category : #'testing' }
GT4AmigaHardwareObserver >> subscriberCount [
	^ mutex critical: [ watch size ]
]

{ #category : #'subscribing' }
GT4AmigaHardwareObserver >> watch: aCollectionOfRegisters for: aSubscriber [
	"aSubscriber needs these registers kept fresh. Re-watching replaces
	 its previous need set. Starts the loop and asks for a prompt sweep so
	 the view fills in without waiting a full cadence."
	mutex critical: [
		watch at: aSubscriber put: aCollectionOfRegisters asArray.
		refreshRequested := true ].
	self ensureRunning
]

{ #category : #'subscribing' }
GT4AmigaHardwareObserver >> unwatch: aSubscriber [
	"aSubscriber is gone (left the scene graph / its page closed). The
	 loop stops itself once nothing is watched and no write is pending."
	mutex critical: [ watch removeKey: aSubscriber ifAbsent: [ ] ]
]

{ #category : #'writing' }
GT4AmigaHardwareObserver >> enqueueWrite: aBlock [
	"Perform a write (a bit toggle, a raw poke) on my loop, serialized
	 with the reads - never on the UI thread. A sweep follows so the
	 written value is read back and the views reflect it."
	mutex critical: [
		writeQueue addLast: aBlock.
		refreshRequested := true ].
	self ensureRunning
]

{ #category : #'writing' }
GT4AmigaHardwareObserver >> refreshNow [
	"Request an out-of-cadence sweep on the next loop tick."
	refreshRequested := true.
	self ensureRunning
]

{ #category : #'worker' }
GT4AmigaHardwareObserver >> stop [
	"Signal the loop to end (e.g. teardown). A later watch/write restarts
	 it with a fresh generation."
	running := false
]

{ #category : #'private' }
GT4AmigaHardwareObserver >> watchedRegisters [
	"The de-duplicated union of every subscriber's need set."
	^ mutex critical: [
		| union |
		union := IdentitySet new.
		watch valuesDo: [ :regs | union addAll: regs ].
		union asArray ]
]

{ #category : #'private' }
GT4AmigaHardwareObserver >> ensureRunning [
	| gen |
	running ifTrue: [ ^ self ].
	running := true.
	generation := generation + 1.
	gen := generation.
	[ self loopGeneration: gen ]
		forkAt: Processor userBackgroundPriority
		named: 'GT4Amiga hardware observer'
]

{ #category : #'private' }
GT4AmigaHardwareObserver >> loopGeneration: myGeneration [
	"Drain queued writes, then sweep the watched union every cadence (or
	 promptly on request). Exit when there is nothing left to do; the
	 generation stamp retires me if a restart already forked a newer loop."
	| idleMs |
	idleMs := 0.
	self sweep.
	[ running and: [ generation = myGeneration ] ] whileTrue: [
		"Wrap the whole tick: the weak registry can be compacted by the
		 finalization process (outside my mutex), so a transient race just
		 costs a skipped tick instead of killing the loop."
		[ | action |
		action := mutex critical: [
			writeQueue isEmpty
				ifTrue: [ nil ]
				ifFalse: [ writeQueue removeFirst ] ].
		action
			ifNotNil: [
				[ action value ] on: Error do: [ :e | ].
				self sweep.
				idleMs := 0 ]
			ifNil: [
				(mutex critical: [ watch isEmpty and: [ writeQueue isEmpty ] ])
					ifTrue: [ running := false ]
					ifFalse: [
						(Delay forMilliseconds: 200) wait.
						idleMs := idleMs + 200.
						(refreshRequested or: [ idleMs >= cadenceMs ]) ifTrue: [
							refreshRequested := false.
							self sweep.
							idleMs := 0 ] ] ] ]
			on: Error do: [ :e | (Delay forMilliseconds: 200) wait ] ]
]

{ #category : #'private' }
GT4AmigaHardwareObserver >> sweep [
	"Read every watched register once and announce. A dead link must not
	 kill the loop (read keeps each register's previous cache)."
	[ self watchedRegisters do: [ :reg | reg read ].
	catalog announcer announce: GT4AmigaRegistersRefreshed new ]
		on: Error
		do: [ :e | ]
]
