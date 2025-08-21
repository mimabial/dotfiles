# Function to insert a command from history N positions ago
_insert_history_n_ago() {
  # Declare a local variable to store the command we'll retrieve
  local command

  # Use 'fc' (fix command) to get a specific line from history
  # -l: list format (shows command without line numbers when combined with -n)
  # -n: suppress line numbers in output
  # "-$1": start position (negative means N commands ago)
  # "-$1": end position (same as start, so we get exactly one command)
  # 2>/dev/null: redirect any error messages to /dev/null (hide errors)
  command=$(fc -ln "-$1" "-$1" 2>/dev/null)
  
  # Remove leading whitespace from the command using parameter expansion
  # ##[[:space:]] means remove the longest match of whitespace characters from the beginning
  command=${command##[[:space:]]}

  # Check if we actually found a command (if command variable is not empty)
  if [[ -n "$command" ]]; then
    # LBUFFER is a zsh special variable that represents the part of command line to the left of cursor
    # Setting it effectively puts our retrieved command on the current command line
    LBUFFER=$command
    
    # Tell zsh to redraw the command line to show the new content
    zle redisplay
  else
    # If no command was found, handle the error case
    
    # Push current input onto the input stack (saves what user might have been typing)
    zle push-input
    
    # Print error message to stderr (file descriptor 2)
    echo "No history found for number: $1" >&2
    
    # Reset the prompt to a clean state
    zle reset-prompt
  fi
}

# Create shortcuts for numbers 1 through 9
# {1..9} is bash/zsh brace expansion that generates: 1 2 3 4 5 6 7 8 9
for i in {1..9}; do
  # Use eval to dynamically create function definitions
  # eval executes the string as if it were typed at the command line
  eval "
    # Create a uniquely named function for each number
    # The function name will be: _insert-history-1-ago, _insert-history-2-ago, etc.
    _insert-history-${i}-ago() {
      # Call our main function with the specific number
      _insert_history_n_ago $i
    }
  "
  
  # Register the function as a zsh line editor (zle) widget
  # -N flag creates a new user-defined widget
  # This makes the function available for key binding
  zle -N "_insert-history-${i}-ago"
  
  # Bind the widget to a key combination
  # -M emacs: use emacs-style key bindings
  # "^[${i}": the key sequence (^[ is ESC/Alt, ${i} is the number)
  # So this creates: Alt+1, Alt+2, Alt+3, etc.
  # The last parameter is the widget name to execute
  bindkey -M emacs "^[${i}" "_insert-history-${i}-ago"
done

# Summary of what this script creates:
# Alt+1 = insert command from 1 position back in history
# Alt+2 = insert command from 2 positions back in history  
# Alt+3 = insert command from 3 positions back in history
# ...
# Alt+9 = insert command from 9 positions back in history
