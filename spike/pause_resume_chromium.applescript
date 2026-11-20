-- Spike: pause every playing media element (all windows/tabs), verify, wait, resume only those, verify.
-- Run via ./run_pause_resume.sh "<Browser>"
on run
	set jsPause to "(function(){var r=[];document.querySelectorAll('video,audio').forEach(function(x,i){if(!x.paused&&!x.ended){x.pause();x.setAttribute('data-hadc','1');r.push(i)}});return JSON.stringify(r)})()"
	set jsState to "(function(){return JSON.stringify([].slice.call(document.querySelectorAll('video,audio')).map(function(x){return {paused:x.paused,t:Math.round(x.currentTime*10)/10,mine:x.getAttribute('data-hadc')}}))})()"
	set jsResume to "(function(){var r=0;document.querySelectorAll('video,audio').forEach(function(x){if(x.getAttribute('data-hadc')==='1'&&x.paused){x.play();r++}x.removeAttribute('data-hadc')});return r})()"
	set out to ""
	set hits to {}
	tell application "__APP__"
		repeat with w in windows
			repeat with t in tabs of w
				try
					set r to execute t javascript jsPause
					if r is not "[]" then
						set end of hits to t
						set out to out & "paused " & r & " in [" & (title of t) & "]" & linefeed
					end if
				end try
			end repeat
		end repeat
		delay 8
		repeat with t in hits
			set out to out & "state after pause: " & (execute t javascript jsState) & linefeed
		end repeat
		repeat with t in hits
			set out to out & "resumed: " & (execute t javascript jsResume) & linefeed
		end repeat
		delay 1
		repeat with t in hits
			set out to out & "state after resume: " & (execute t javascript jsState) & linefeed
		end repeat
	end tell
	return out
end run
