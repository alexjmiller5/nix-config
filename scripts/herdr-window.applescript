on run argv
  tell application "Ghostty"
    set surfaceConfig to new surface configuration
    set initial working directory of surfaceConfig to item 1 of argv
    set command of surfaceConfig to quoted form of item 2 of argv
    set herdrWindow to new window with configuration surfaceConfig
    set herdrTerminal to focused terminal of selected tab of herdrWindow
    if not (perform action "activate_key_table:herdr" on herdrTerminal) then
      error "Herdr key table unavailable. Reload the Ghostty configuration."
    end if
    activate window herdrWindow
  end tell
end run
