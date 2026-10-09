on run argv
  -- Open the Herdr window over the Ghostty window `hdr` was typed in, at the
  -- same position and size. Ghostty's scripting has no window bounds, so
  -- System Events carries them (needs Ghostty in Accessibility); without that
  -- grant, or when hdr ran outside Ghostty, the window keeps Ghostty's default.
  set oldFrame to missing value
  try
    tell application "System Events" to tell process "Ghostty"
      if frontmost and (count of windows) > 0 then
        set oldCount to count of windows
        set oldFrame to {position, size} of window 1
      end if
    end tell
  end try

  tell application "Ghostty"
    set surfaceConfig to new surface configuration
    set initial working directory of surfaceConfig to item 1 of argv
    set command of surfaceConfig to "/bin/zsh -lc " & quoted form of item 2 of argv
    set herdrWindow to new window with configuration surfaceConfig
    activate window herdrWindow
  end tell

  if oldFrame is not missing value then
    try
      tell application "System Events" to tell process "Ghostty"
        repeat 20 times
          if (count of windows) > oldCount then exit repeat
          delay 0.1
        end repeat
        set position of window 1 to item 1 of oldFrame
        set size of window 1 to item 2 of oldFrame
      end tell
    end try
  end if
end run
