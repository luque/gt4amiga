Class {
	#name : #GT4AmigaSnippetRegistration,
	#superclass : #Object,
	#category : #'GT4Amiga-Lepiter'
}

{ #category : #registration }
GT4AmigaSnippetRegistration class >> register [
	"Register GT4AmigaSnippet with GToolkit's Lepiter subsystem.

	 JSON round-tripping: GToolkit's LeJsonV4 auto-discovers LeSnippet subclasses
	 via LeSnippet allSubclasses and uses typeName to build the __type mapping.
	 So just loading this package is enough for serialization/deserialization.

	 This method handles additional registrations:
	 - 'New Snippet' menu entry in Lepiter pages
	 - Optional: syntax highlighting styler

	 Call once after loading GT4Amiga-Lepiter, e.g. from a startup action."

	self registerInNewSnippetMenu.
	self registerInJsonV4IfNeeded
]

{ #category : #registration }
GT4AmigaSnippetRegistration class >> registerInNewSnippetMenu [
	"Add GT4AmigaSnippet to the + menu in Lepiter pages."
	| registryClass |
	registryClass := Smalltalk globals
		at: #LeSnippetTypeRegistry
		ifAbsent: [ ^ self ].
	(registryClass respondsTo: #uniqueInstance)
		ifFalse: [ ^ self ].
	[ registryClass uniqueInstance register: GT4AmigaSnippet ]
		on: Error
		do: [ :e | "Ignore - menu registration is optional" ]
]

{ #category : #registration }
GT4AmigaSnippetRegistration class >> registerInJsonV4IfNeeded [
	"Ensure LeJsonV4 can handle amiga68kSnippet __type.
	 In most GToolkit versions this is automatic via LeSnippet allSubclasses.
	 This method adds an explicit entry if the auto-discovery is not active."
	| jsonClass |
	jsonClass := Smalltalk globals at: #LeJsonV4 ifAbsent: [ ^ self ].
	(jsonClass respondsTo: #registerSnippetClass:) ifTrue: [
		[ jsonClass uniqueInstance registerSnippetClass: GT4AmigaSnippet ]
			on: Error
			do: [ :e | "Already registered or not needed" ] ]
]

{ #category : #'load actions' }
GT4AmigaSnippetRegistration class >> postLoad [
	"Called automatically by Metacello after loading the package.
	 Triggers registration without manual intervention."
	self register
]
