on run argv
  tell application "Ghostty"
    set surfaceConfig to new surface configuration
    set initial working directory of surfaceConfig to item 1 of argv
    set command of surfaceConfig to quoted form of item 2 of argv
    set herdrWindow to new window with configuration surfaceConfig
    activate window herdrWindow
  end tell
end run
