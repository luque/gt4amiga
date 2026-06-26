Class {
	#name : 'GT4AmigaMcpLepiterServer',
	#superclass : 'GT4AmigaMcpEvalServer',
	#instVars : [],
	#category : 'GT4Amiga-MCP',
	#package : 'GT4Amiga-MCP'
}

{ #category : 'initialization' }
GT4AmigaMcpLepiterServer >> initialize [
	super initialize.
	self addTool: self createListPagesTool.
	self addTool: self createGetPageTool.
	self addTool: self createCreatePageTool.
	self addTool: self createAddSnippetTool.
	self addTool: self createGetClassInfoTool
]

{ #category : 'tools' }
GT4AmigaMcpLepiterServer >> createListPagesTool [
	^ GtLlmFunctionTool new
		name: 'list-pages';
		parameters: { 'dbName' };
		description: 'Lists all page titles in a Lepiter database by name';
		block: [ :call |
			| dbName db |
			dbName := call arguments at: 'dbName'.
			db := LeDatabasesRegistry default currentLoadedDefaultLogicalDatabase
				databases detect: [ :d | d databaseName = dbName ].
			String streamContents: [ :s |
				db pages do: [ :p | s nextPutAll: p title; nextPut: $,; nextPut: $  ] ] ]
]

{ #category : 'tools' }
GT4AmigaMcpLepiterServer >> createGetPageTool [
	^ GtLlmFunctionTool new
		name: 'get-page';
		parameters: { 'dbName'. 'pageTitle' };
		description: 'Returns the content of a Lepiter page as plain text';
		block: [ :call |
			| dbName pageTitle db page |
			dbName := call arguments at: 'dbName'.
			pageTitle := call arguments at: 'pageTitle'.
			db := LeDatabasesRegistry default currentLoadedDefaultLogicalDatabase
				databases detect: [ :d | d databaseName = dbName ].
			page := db pageNamed: pageTitle.
			String streamContents: [ :s |
				page children do: [ :snippet |
					(snippet isKindOf: LeTextSnippet) ifTrue: [
						s nextPutAll: snippet string; nextPut: Character lf ].
					(snippet isKindOf: LePharoSnippet) ifTrue: [
						s nextPutAll: snippet code; nextPut: Character lf ].
					(snippet isKindOf: LeExampleSnippet) ifTrue: [
						s nextPutAll: snippet exampleBehaviorName;
						nextPutAll: '>>';
						nextPutAll: snippet exampleSelector; nextPut: Character lf ].
					(snippet isKindOf: GT4AmigaSnippet) ifTrue: [
						s nextPutAll: snippet code; nextPut: Character lf ] ] ] ]
]

{ #category : 'tools' }
GT4AmigaMcpLepiterServer >> createCreatePageTool [
	^ GtLlmFunctionTool new
		name: 'create-page';
		parameters: { 'dbName'. 'pageTitle' };
		description: 'Creates a new Lepiter page in the named database';
		block: [ :call |
			| dbName pageTitle db page |
			dbName := call arguments at: 'dbName'.
			pageTitle := call arguments at: 'pageTitle'.
			db := LeDatabasesRegistry default currentLoadedDefaultLogicalDatabase
				databases detect: [ :d | d databaseName = dbName ].
			page := LePage named: pageTitle.
			db addPage: page.
			'ok' ]
]

{ #category : 'tools' }
GT4AmigaMcpLepiterServer >> createAddSnippetTool [
	^ GtLlmFunctionTool new
		name: 'add-snippet';
		parameters: { 'dbName'. 'pageTitle'. 'snippetType'. 'content' };
		description: 'Adds a snippet to a Lepiter page. snippetType: text | pharo | example | amiga68k. For example snippets content must be ClassName>>selector';
		block: [ :call |
			| dbName pageTitle snippetType content db page snippet idx |
			dbName := call arguments at: 'dbName'.
			pageTitle := call arguments at: 'pageTitle'.
			snippetType := call arguments at: 'snippetType'.
			content := call arguments at: 'content'.
			db := LeDatabasesRegistry default currentLoadedDefaultLogicalDatabase
				databases detect: [ :d | d databaseName = dbName ].
			page := db pageNamed: pageTitle.
			snippet := snippetType = 'text'
				ifTrue: [ LeTextSnippet new string: content ]
				ifFalse: [ snippetType = 'pharo'
					ifTrue: [ LePharoSnippet new code: content ]
					ifFalse: [ snippetType = 'amiga68k'
						ifTrue: [ GT4AmigaSnippet new code: content ]
						ifFalse: [
							idx := content indexOfSubCollection: '>>'.
							LeExampleSnippet new
								exampleBehaviorName: (content copyFrom: 1 to: idx - 1);
								exampleSelector: (content copyFrom: idx + 2 to: content size);
								previewShowSelector: 'gtViewsFor:';
								previewHeight: 200;
								codeExpanded: true;
								previewExpanded: false ] ] ].
			page addSnippet: snippet.
			'ok' ]
]

{ #category : 'tools' }
GT4AmigaMcpLepiterServer >> createGetClassInfoTool [
	^ GtLlmFunctionTool new
		name: 'get-class-info';
		parameters: { 'className' };
		description: 'Returns information about a Pharo class: superclass, category, comment, instance/class variables, subclasses, and method selectors';
		block: [ :call |
			| className cls |
			className := call arguments at: 'className'.
			cls := Smalltalk at: className asSymbol ifAbsent: [ nil ].
			cls isNil
				ifTrue: [ 'Class not found: ' , className ]
				ifFalse: [
					String streamContents: [ :s |
						s nextPutAll: 'Name: '; nextPutAll: cls name; nextPut: Character lf.
						s nextPutAll: 'Superclass: '; nextPutAll: cls superclass name; nextPut: Character lf.
						s nextPutAll: 'Category: '; nextPutAll: cls category; nextPut: Character lf.
						s nextPutAll: 'Comment: '; nextPutAll: (cls comment ifNil: [ '(none)' ]); nextPut: Character lf.
						s nextPutAll: 'Instance variables: '; nextPutAll: cls instVarNames printString; nextPut: Character lf.
						s nextPutAll: 'Class variables: '; nextPutAll: cls classVarNames printString; nextPut: Character lf.
						s nextPutAll: 'Subclasses: ';
							nextPutAll: (cls subclasses collect: [ :sub | sub name ]) printString; nextPut: Character lf.
						s nextPutAll: 'Instance methods (' , cls methodDict size printString , '): '.
						cls methodDict keysSortedSafely do: [ :sel | s nextPutAll: sel; nextPut: $,; nextPut: $  ].
						s nextPut: Character lf.
						s nextPutAll: 'Class methods (' , cls class methodDict size printString , '): '.
						cls class methodDict keysSortedSafely do: [ :sel | s nextPutAll: sel; nextPut: $,; nextPut: $  ] ] ] ]
]
