Class {
	#name : #GT4FSUAERunner,
	#superclass : #Object,
	#instVars : [
		'configuration',
		'fsuaeProcess',
		'serialSocket',
		'outputBuffer',
		'configFile'
	],
	#classVars : [ 'Default' ],
	#category : #'GT4Amiga-FSUAE'
}

{ #category : #accessing }
GT4FSUAERunner class >> default [
	^ Default ifNil: [ Default := self new ]
]

{ #category : #accessing }
GT4FSUAERunner class >> default: aRunner [
	Default := aRunner
]

{ #category : #'instance creation' }
GT4FSUAERunner class >> new [
	^ super new initialize
]

{ #category : #'instance creation' }
GT4FSUAERunner class >> withConfiguration: aConfiguration [
	^ self new
		configuration: aConfiguration;
		yourself
]

{ #category : #accessing }
GT4FSUAERunner >> serialSocket [
	"Public accessor for the live serial TCP socket, used by GT4AmigaMonitorClient."
	^ serialSocket
]

{ #category : #initialization }
GT4FSUAERunner >> initialize [
	configuration := GT4AmigaConfiguration default.
	outputBuffer := ''
]

{ #category : #accessing }
GT4FSUAERunner >> configuration [
	^ configuration
]

{ #category : #accessing }
GT4FSUAERunner >> configuration: aConfiguration [
	configuration := aConfiguration
]

{ #category : #lifecycle }
GT4FSUAERunner >> launch [
	"Write config to ~/.config/fs-uae/fs-uae.conf (the only path FS-UAE reads
	 during early-init, where hard drives and kickstarts_dir are processed)
	 then start FS-UAE with no --config= argument."
	self isRunning ifTrue: [ ^ self ].
	self prepareSharedDirectory.
	self writeFSUAEConfig.
	fsuaeProcess := GtSubprocessWithInMemoryOutput new
		command: configuration fsuaePath;
		arguments: #();
		run.
	"Give FS-UAE time to start and the Amiga to boot"
	(Delay forSeconds: 5) wait
]

{ #category : #lifecycle }
GT4FSUAERunner >> stop [
	"Terminate the FS-UAE process."
	self disconnectSerial.
	(fsuaeProcess isNil or: [ fsuaeProcess isRunning not ]) ifTrue: [ ^ self ].
	fsuaeProcess terminate.
	fsuaeProcess wait.
	fsuaeProcess := nil
]

{ #category : #lifecycle }
GT4FSUAERunner >> restart [
	self stop.
	(Delay forMilliseconds: 500) wait.
	self launch
]

{ #category : #testing }
GT4FSUAERunner >> isRunning [
	^ fsuaeProcess isNil not and: [ fsuaeProcess isRunning ]
]

{ #category : #running }
GT4FSUAERunner >> run: anAssemblyResult [
	"Deploy the assembled program and execute it through the resident
	 monitor (opcode X): the program runs as its own AmigaDOS process with
	 Output() captured to shared/outgoing/output, whose contents are
	 returned here. The monitor is the only resident Amiga-side program -
	 the polling watcher script, its trigger file, the done marker and the
	 raw serial capture are all retired. The monitor is launched at boot
	 by S:User-Startup (one-time HDF setup, see the README)."
	| monitor mailbox |
	anAssemblyResult success ifFalse: [
		^ 'Assembly failed - cannot run: ' , anAssemblyResult stderr ].
	self isRunning ifFalse: [ self launch ].
	(self waitForMonitorTimeout: 90) ifFalse: [
		^ 'Monitor not responding. Is it installed? (S:User-Startup must Run GT4A:incoming/monitor - see the README)' ].
	self deployProgram: anAssemblyResult outputFile.
	monitor := (Smalltalk at: #GT4AmigaMonitorClient) default.
	mailbox := monitor executeProgram.
	mailbox ifNil: [
		^ 'Monitor did not launch the program (a previous program may still be running, or LoadSeg failed)' ].
	(monitor waitForProgramAt: mailbox timeout: 60 seconds) ifNil: [
		^ 'Program did not finish within 60 seconds (or failed to launch - poll the mailbox for details)' ].
	^ (monitor capturedOutput ifNil: [ '' ]) trimmed
]

{ #category : #running }
GT4FSUAERunner >> waitForMonitorTimeout: seconds [
	"Answer true once the resident monitor responds. After launch the
	 Amiga needs tens of seconds to boot to the point where S:User-Startup
	 runs it, so the first ping of a session can take a while: keep
	 pinging (workbenchScreenPointer is idempotent and side-effect free)
	 until the deadline. GT4AmigaMonitorClient is looked up by name: the
	 Bridge package loads after this one (it requires GT4Amiga-FSUAE), so
	 a direct reference here would be undeclared at load time."
	| deadline |
	deadline := DateAndTime now + (Duration seconds: seconds).
	[ DateAndTime now < deadline ] whileTrue: [
		(Smalltalk at: #GT4AmigaMonitorClient) default workbenchScreenPointer
			ifNotNil: [ ^ true ].
		(Delay forSeconds: 2) wait ].
	^ false
]

{ #category : #running }
GT4FSUAERunner >> deployProgram: aProgramFile [
	"Copy the program to shared/incoming/program, where the monitor's X
	 opcode (LoadSeg GT4A:incoming/program) expects it. Clears the previous
	 captured output so a stale file can never be mistaken for this run's."
	| incoming output |
	incoming := configuration sharedDirectory / 'incoming'.
	incoming ensureCreateDirectory.
	(incoming / 'program') exists ifTrue: [ (incoming / 'program') delete ].
	output := configuration sharedDirectory / 'outgoing' / 'output'.
	output exists ifTrue: [ output delete ].
	aProgramFile copyTo: incoming / 'program'
]

{ #category : #'serial communication' }
GT4FSUAERunner >> connectSerial [
	"Connect to the monitor's TCP endpoint: FS-UAE's serial bridge on
	 localhost, or a real Amiga's bsdsocket server across the network
	 (configuration monitorHost). Uses an explicit short timeout: Socket
	 standardTimeout is too long (tens of seconds). Retries a few times
	 since FS-UAE may still be booting when this is first called.
	 Checking isConnected (not just isNil) matters: a socket whose peer
	 closed goes stale (visible as CLOSE-WAIT) but stays non-nil, so a
	 pure isNil guard would keep reusing a dead connection forever."
	(serialSocket isNil not and: [ serialSocket isConnected ]) ifTrue: [ ^ self ].
	serialSocket isNil ifFalse: [
		[ serialSocket close ] on: Error do: [ :e | ].
		serialSocket := nil ].
	3 timesRepeat: [
		[ serialSocket := Socket newTCP.
		  serialSocket
			connectTo: (NetNameResolver addressForName: configuration monitorHost)
			port: configuration serialPort
			waitForConnectionFor: 3.
		  serialSocket isConnected ifTrue: [ ^ self ] ]
			on: Error
			do: [ :e | serialSocket := nil ].
		(Delay forSeconds: 2) wait ]
]

{ #category : #'serial communication' }
GT4FSUAERunner >> disconnectSerial [
	serialSocket isNil ifTrue: [ ^ self ].
	[ serialSocket close ] on: Error do: [ :e | ].
	serialSocket := nil
]

{ #category : #'private - setup' }
GT4FSUAERunner >> prepareSharedDirectory [
	| shared |
	shared := configuration sharedDirectory.
	(shared / 'incoming') ensureCreateDirectory.
	(shared / 'outgoing') ensureCreateDirectory
]

{ #category : #'private - setup' }
GT4FSUAERunner >> writeFSUAEConfig [
	"Write the FS-UAE config to ~/.config/fs-uae/fs-uae.conf.
	 FS-UAE reads this file during early initialisation — the only phase
	 where hard_drive_*, kickstarts_dir and other hardware options are
	 processed. A session config passed via --config= is read later and
	 silently ignores those options."
	| configRef content |
	configRef := (FileLocator home / '.config' / 'fs-uae' / 'fs-uae.conf') asFileReference.
	configRef parent ensureCreateDirectory.
	content := self fsuaeConfigContent.
	configRef exists ifTrue: [ configRef delete ].
	configRef writeStreamDo: [ :s | s nextPutAll: content ].
	^ configRef
]

{ #category : #'private - setup' }
GT4FSUAERunner >> fsuaeConfigContent [
	"Generate the FS-UAE config file content."
	^ String streamContents: [ :s |
		| lf |
		lf := String lf.
		s nextPutAll: 'amiga_model = ' , configuration amigaModel; nextPutAll: lf.
		s nextPutAll: 'chip_memory = ' , configuration chipMemory printString; nextPutAll: lf.
		configuration fastMemory > 0 ifTrue: [
			s nextPutAll: 'fast_memory = ' , configuration fastMemory printString; nextPutAll: lf ].
		configuration kickstartPath isNil not ifTrue: [
			s nextPutAll: 'kickstarts_dir = ' , configuration kickstartPath parent fullName; nextPutAll: lf.
			s nextPutAll: 'kickstart_file = ' , configuration kickstartPath fullName; nextPutAll: lf ].
		configuration workbenchHdfPath isNil not ifTrue: [
			s nextPutAll: 'hard_drive_0 = ' , configuration workbenchHdfPath fullName; nextPutAll: lf.
			s nextPutAll: 'hard_drive_0_label = DH0'; nextPutAll: lf ].
		s nextPutAll: 'hard_drive_1 = ' , configuration sharedDirectory fullName; nextPutAll: lf.
		s nextPutAll: 'hard_drive_1_label = GT4A'; nextPutAll: lf.
		s nextPutAll: 'serial_port = tcp://127.0.0.1:' , configuration serialPort printString; nextPutAll: lf.
		s nextPutAll: 'fullscreen = 0'; nextPutAll: lf.
		s nextPutAll: 'window_width = 720'; nextPutAll: lf.
		s nextPutAll: 'window_height = 568'; nextPutAll: lf ]
]

{ #category : #'gt-extensions' }
GT4FSUAERunner >> gtViewStatusFor: aView [
	<gtView>
	^ aView columnedList
		title: 'Status';
		priority: 5;
		items: [ self statusPairs ];
		column: 'Key' text: [ :pair | pair key ] width: 150;
		column: 'Value' text: [ :pair | pair value printString ]
]

{ #category : #private }
GT4FSUAERunner >> statusPairs [
	^ {
		'Running' -> self isRunning.
		'Amiga model' -> configuration amigaModel.
		'Shared dir' -> configuration sharedDirectory fullName.
		'Serial port' -> configuration serialPort.
		'Serial connected' -> serialSocket isNil not }
]

{ #category : #'gt-extensions' }
GT4FSUAERunner >> gtActionLaunchFor: anAction [
	<gtAction>
	self isRunning ifTrue: [ ^ anAction noAction ].
	^ anAction button
		label: 'Launch FS-UAE';
		action: [ self launch ]
]

{ #category : #'gt-extensions' }
GT4FSUAERunner >> gtActionStopFor: anAction [
	<gtAction>
	self isRunning ifFalse: [ ^ anAction noAction ].
	^ anAction button
		label: 'Stop';
		action: [ self stop ]
]
