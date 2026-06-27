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
	"Start FS-UAE with the current configuration.
	 The Amiga will boot and wait for programs via the shared directory."
	self isRunning ifTrue: [ ^ self ].
	self prepareSharedDirectory.
	configFile := self writeFSUAEConfig.
	fsuaeProcess := GtSubprocessWithInMemoryOutput new
		command: configuration fsuaePath;
		arguments: { '--config=' , configFile fullName };
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
	outputText := self captureOutputWithTimeout: 10.
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
	"Connect to the FS-UAE serial port (TCP socket)."
	serialSocket isNil ifFalse: [ ^ self ].
	[ serialSocket := Socket newTCP.
	  serialSocket connectTo: NetNameResolver localHostAddress port: configuration serialPort.
	] on: Error do: [ :e | serialSocket := nil ]
]

{ #category : #'serial communication' }
GT4FSUAERunner >> disconnectSerial [
	serialSocket isNil ifTrue: [ ^ self ].
	[ serialSocket close ] on: Error do: [ :e | ].
	serialSocket := nil
]

{ #category : #'serial communication' }
GT4FSUAERunner >> captureOutputWithTimeout: seconds [
	"Read from the serial TCP socket until timeout or terminator received.
	 Programs signal completion by printing a chr(0) on serial output."
	| deadline result chunk |
	self connectSerial.
	serialSocket isNil ifTrue: [ ^ '' ].
	deadline := DateAndTime now + (Duration seconds: seconds).
	result := String new writeStream.
	[
		DateAndTime now < deadline and: [
			result contents includesSubString: (String with: Character null) ] not
	] whileTrue: [
		serialSocket isConnected ifFalse: [ ^ result contents ].
		chunk := self readAvailableFromSerial.
		chunk isEmpty ifFalse: [ result nextPutAll: chunk ].
		chunk isEmpty ifTrue: [ (Delay forMilliseconds: 100) wait ]
	].
	^ result contents copyReplaceAll: (String with: Character null) with: ''
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
	"Write the fs-uae config file to a temp location and return it."
	| configRef content |
	configRef := (FileLocator temp / 'gt4amiga') asFileReference.
	configRef ensureCreateDirectory.
	configRef := configRef / 'gt4amiga.fs-uae'.
	content := self fsuaeConfigContent.
	configRef writeStreamDo: [ :s | s nextPutAll: content ].
	^ configRef
]

{ #category : #'private - setup' }
GT4FSUAERunner >> fsuaeConfigContent [
	"Generate the FS-UAE config file content."
	^ String streamContents: [ :s |
		s nextPutAll: '[config]'; nl.
		s nextPutAll: 'amiga_model = ' , configuration amigaModel; nl.
		s nextPutAll: 'chip_memory = ' , configuration chipMemory printString; nl.
		configuration fastMemory > 0 ifTrue: [
			s nextPutAll: 'fast_memory = ' , configuration fastMemory printString; nl ].
		configuration kickstartPath isNil not ifTrue: [
			s nextPutAll: 'kickstart_file = ' , configuration kickstartPath fullName; nl ].
		configuration workbenchHdfPath isNil not ifTrue: [
			s nextPutAll: 'hard_drive_0 = ' , configuration workbenchHdfPath fullName; nl.
			s nextPutAll: 'hard_drive_0_label = DH0'; nl ].
		s nextPutAll: 'hard_drive_1 = ' , configuration sharedDirectory fullName; nl.
		s nextPutAll: 'hard_drive_1_label = GT4A'; nl.
		s nextPutAll: 'serial_port = tcp://localhost:' , configuration serialPort printString; nl.
		s nextPutAll: 'fullscreen = 0'; nl.
		s nextPutAll: 'window_width = 720'; nl.
		s nextPutAll: 'window_height = 568'; nl ]
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
