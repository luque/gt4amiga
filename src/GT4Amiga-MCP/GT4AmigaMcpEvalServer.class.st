Class {
	#name : 'GT4AmigaMcpEvalServer',
	#superclass : 'GtMcpServer',
	#instVars : [],
	#category : 'GT4Amiga-MCP',
	#package : 'GT4Amiga-MCP'
}

{ #category : 'initialization' }
GT4AmigaMcpEvalServer >> initialize [
	super initialize.
	port := 8765.
	self addTool: self createEvalTool
]

{ #category : 'private' }
GT4AmigaMcpEvalServer >> createEvalTool [
	^ GtLlmFunctionTool new
		name: 'eval';
		parameters: { 'code' };
		description: 'Evaluates a Smalltalk expression and returns the result as a string';
		block: [ :call |
			| code |
			code := call arguments at: 'code'.
			(Smalltalk compiler evaluate: code) asString ]
]

{ #category : 'request handling' }
GT4AmigaMcpEvalServer >> handleRequest: request [
	| jsonRpc response jsonRpcResult |
	[ jsonRpc := GtMcpJsonRpc on: (STONJSON fromString: request entity contents) ]
		on: Error
		do: [ ^ ZnResponse badRequest: request ].
	[ jsonRpcResult := self dispatch: jsonRpc ]
		on: Error
		do: [ :anError |
			errors add: anError freeze.
			self isDebug ifTrue: [ anError signal ].
			^ ZnResponse serverError: 'Error invoking MCP: ' , anError asString ].
	response := (GtMcpJsonRpc new
		id: jsonRpc id;
		result: jsonRpcResult) asZnResponse.
	history add: request -> response.
	^ response
]
