"
Announced by a GT4AmigaMachine after a background refresh has re-read the memory gauges (AvailMem, ExecBase bounds) or a memory region window from the machine. Views subscribe to it (updateWhen) so they re-render the fresh cache without ever doing serial I/O on the UI thread themselves.
"
Class {
	#name : #GT4AmigaMachineRefreshed,
	#superclass : #Announcement,
	#category : #'GT4Amiga-Hardware'
}
