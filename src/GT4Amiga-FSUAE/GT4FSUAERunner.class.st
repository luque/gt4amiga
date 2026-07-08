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
	"Deploy the assembled program and trigger execution on the Amiga.
	 Returns the captured serial output (stdout from the Amiga program)."
	| outputText |
	anAssemblyResult success ifFalse: [
		^ 'Assembly failed - cannot run: ' , anAssemblyResult stderr ].
	self isRunning ifFalse: [ self launch ].
	self deployProgram: anAssemblyResult outputFile.
	outputText := self captureOutputWithTimeout: 60.
	^ outputText
]

{ #category : #running }
GT4FSUAERunner >> deployProgram: aProgramFile [
	"Copy the program to the shared directory and write the trigger file.
	 The AmigaDOS watcher script detects the trigger and runs the program."
	| incoming program trigger |
	incoming := configuration sharedDirectory / 'incoming'.
	incoming ensureCreateDirectory.

	"Remove any previous run artifacts"
	(incoming / 'trigger') exists ifTrue: [ (incoming / 'trigger') delete ].
	(incoming / 'program') exists ifTrue: [ (incoming / 'program') delete ].
	(configuration sharedDirectory / 'outgoing' / 'output.txt') exists
		ifTrue: [ (configuration sharedDirectory / 'outgoing' / 'output.txt') delete ].

	"Copy the new program"
	program := incoming / 'program'.
	aProgramFile copyTo: program.

	"Write the trigger last (the watcher polls for this)"
	trigger := incoming / 'trigger'.
	trigger writeStreamDo: [ :s | s nextPutAll: 'run' ]
]

{ #category : #'serial communication' }
GT4FSUAERunner >> connectSerial [
	"Connect to the FS-UAE serial port (TCP socket).
	 Uses an explicit short timeout: Socket standardTimeout is too long
	 (tens of seconds), which made connection attempts appear to hang
	 when FS-UAE's listener wasn't ready yet. Retries a few times since
	 FS-UAE may still be booting when this is first called.
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
			connectTo: (NetNameResolver addressForName: '127.0.0.1')
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

{ #category : #'serial communication' }
GT4FSUAERunner >> captureOutputWithTimeout: seconds [
	"Read from the serial TCP socket until the <<GT4A-DONE>> marker or timeout.
	 The watcher script sends this marker after the program finishes."
	| deadline result chunk |
	self connectSerial.
	serialSocket isNil ifTrue: [ ^ '' ].
	deadline := DateAndTime now + (Duration seconds: seconds).
	result := String new writeStream.
	[
		DateAndTime now < deadline and: [
			(result contents includesSubstring: '<<GT4A-DONE>>') not ]
	] whileTrue: [
		serialSocket isConnected ifFalse: [ ^ result contents ].
		chunk := self readAvailableFromSerial.
		chunk isEmpty ifFalse: [ result nextPutAll: chunk ].
		chunk isEmpty ifTrue: [ (Delay forMilliseconds: 100) wait ]
	].
	^ (result contents copyReplaceAll: '<<GT4A-DONE>>' with: '') trimmed
]

{ #category : #'serial communication' }
GT4FSUAERunner >> readAvailableFromSerial [
	"Non-blocking read of whatever is available on the serial socket."
	| bytes |
	[ bytes := serialSocket receiveDataTimeout: 100 ]
		on: Error do: [ :e | ^ '' ].
	^ bytes ifNil: [ '' ] ifNotNil: [ :b | b asString ]
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
