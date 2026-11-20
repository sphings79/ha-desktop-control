-- Spike: re-resolve the Brave window by index each step (the window list changes while fullscreen transitions run).
on winState()
	tell application "System Events" to tell process "Brave Browser"
		set o to ""
		repeat with w in windows
			set o to o & "[fs=" & (value of attribute "AXFullScreen" of w) & " min=" & (value of attribute "AXMinimized" of w) & "] "
		end repeat
		return o
	end tell
end winState
on run
	set out to "start " & my winState() & linefeed
	tell application "System Events" to tell process "Brave Browser" to set value of attribute "AXMinimized" of window 1 to true
	delay 2
	set out to out & "minimized " & my winState() & linefeed
	tell application "System Events" to tell process "Brave Browser" to set value of attribute "AXMinimized" of window 1 to false
	delay 2
	set out to out & "unminimized " & my winState() & linefeed
	tell application "System Events" to tell process "Brave Browser" to set value of attribute "AXFullScreen" of window 1 to true
	delay 3
	set out to out & "window fullscreen " & my winState() & linefeed
	tell application "Brave Browser" to set r to execute (active tab of window 1) javascript "String(!!document.fullscreenElement)"
	set out to out & "element fullscreen: " & r & linefeed
	tell application "System Events" to tell process "Brave Browser" to set value of attribute "AXFullScreen" of window 1 to false
	delay 3
	set out to out & "back to normal " & my winState() & linefeed
	return out
end run
