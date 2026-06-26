Class {
	#name : #GT4AmigaSnippetViewModel,
	#superclass : #LeSnippetViewModel,
	#category : #'GT4Amiga-Lepiter'
}

{ #category : #accessing }
GT4AmigaSnippetViewModel >> snippet [
	^ snippetModel
]

{ #category : #'api - element' }
GT4AmigaSnippetViewModel >> snippetElementClass [
	^ GT4AmigaSnippetElement
]

{ #category : #'api - element' }
GT4AmigaSnippetViewModel >> createContentElement [
	^ GT4AmigaSnippetElement new
		snippetViewModel: self;
		yourself
]

{ #category : #'api - element' }
GT4AmigaSnippetViewModel >> snippetView [
	"Called by some GToolkit versions to get the element."
	^ self createContentElement
]
