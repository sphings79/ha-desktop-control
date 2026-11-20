-- Spike: find the fullscreen window of Brave, exit fullscreen, minimize, restore, re-enter fullscreen.
on fsWindowInfo()
	tell application "System Events" to tell process "Brave Browser"
		set o to ""
		repeat with w in windows
			set o to o & "[" & (value of attribute "AXFullScreen" of w) & "/" & (value of attribute "AXMinimized" of w) & "] "
		end repeat
		return o
	end tell
end fsWindowInfo

on run
	set out to "start: " & my fsWindowInfo() & linefeed
	tell application "System Events" to tell process "Brave Browser"
		set target to missing value
		repeat with w in windows
			if value of attribute "AXFullScreen" of w is true then set target to w
		end repeat
		if target is missing value then return "no fullscreen window"
		set value of attribute "AXFullScreen" of target to false
	end tell
	delay 2
	set out to out & "after exit fs: " & my fsWindowInfo() & linefeed
	tell application "System Events" to tell process "Brave Browser"
		set value of attribute "AXMinimized" of target to true
	end tell
	delay 2
	set out to out & "after minimize: " & my fsWindowInfo() & linefeed
	tell application "System Events" to tell process "Brave Browser"
		set value of attribute "AXMinimized" of target to false
	end tell
	delay 2
	set out to out & "after unminimize: " & my fsWindowInfo() & linefeed
	tell application "System Events" to tell process "Brave Browser"
		set value of attribute "AXFullScreen" of target to true
	end tell
	delay 2
	set out to out & "after re-enter fs: " & my fsWindowInfo() & linefeed
	return out
end run
