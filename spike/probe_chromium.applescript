-- Read-only probe: lists tabs (host only) and media element state. Does NOT pause anything.
-- Usage: ./run_probe.sh "Brave Browser"  (app name is substituted for __APP__ because the dictionary must resolve at compile time)
on run
	set js to "(function(){var m=[].slice.call(document.querySelectorAll('video,audio'));return JSON.stringify({n:m.length,playing:m.filter(function(x){return !x.paused&&!x.ended}).length,fs:!!document.fullscreenElement});})()"
	set out to ""
	tell application "__APP__"
		repeat with w in windows
			set wid to id of w
			set ti to 0
			repeat with t in tabs of w
				set ti to ti + 1
				set u to URL of t
				set h to my hostOf(u)
				try
					set r to execute t javascript js
				on error e
					set r to "ERR: " & e
				end try
				set out to out & "win " & wid & " tab " & ti & " [" & h & "] " & r & linefeed
			end repeat
		end repeat
	end tell
	return out
end run

on hostOf(u)
	set AppleScript's text item delimiters to "/"
	set parts to text items of u
	set AppleScript's text item delimiters to ""
	if (count of parts) > 2 then return item 3 of parts
	return u
end hostOf
