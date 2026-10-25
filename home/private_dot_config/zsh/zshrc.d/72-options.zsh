# Shell options. After 70-plugins, like when the yupps-zsh plugin set them,
# so they win over oh-my-zsh's lib/history.zsh and zsh-utils. zstyles.d needs
# NOMATCH off: an unquoted # there would otherwise be a failing glob.

# Prompt
setopt PROMPT_SUBST # expand parameters/commands in prompts

# History
setopt HIST_IGNORE_ALL_DUPS # remove all earlier duplicate lines
setopt APPEND_HISTORY # history appends to existing file
setopt SHARE_HISTORY # import new commands from the history file also in other zsh-session
setopt EXTENDED_HISTORY # save each commands beginning timestamp and the duration to the history file
setopt HIST_REDUCE_BLANKS # trim multiple insignificant blanks in history
setopt HIST_IGNORE_SPACE # don't store lines starting with space

# Globbing / input
setopt EXTENDED_GLOB # treat special characters as part of patterns
unsetopt CORRECT_ALL # don't try to correct the spelling of all arguments in a line
unsetopt FLOW_CONTROL # disable Ctrl-S/Ctrl-Q flow control
setopt MULTIOS # allows multiple input and output redirections
setopt AUTO_CD # if the command is a directory and cannot be executed, cd into it
setopt CLOBBER # allow > redirection to truncate existing files
setopt BRACE_CCL # allow brace character class list expansion
unsetopt BEEP # do not beep on errors
unsetopt NOMATCH # pass unmatched globs through instead of 'zsh: no matches found'
setopt INTERACTIVE_COMMENTS # allow use of comments in interactive code

# Completion
setopt AUTO_PARAM_SLASH # complete folders with / at end
setopt LIST_TYPES # mark type of completion suggestions
setopt HASH_LIST_ALL # hash the entire command path before completing
setopt COMPLETE_IN_WORD # allow completion from within a word/phrase
setopt ALWAYS_TO_END # move cursor to the end of a completed word

# Jobs
setopt LONG_LIST_JOBS # list jobs in the long format by default
setopt AUTO_RESUME # attempt to resume existing job before creating a new process
setopt NOTIFY # report status of background jobs immediately

# Safety
unsetopt SHORT_LOOPS # disable short loop forms, can be confusing
unsetopt RM_STAR_SILENT # ask for confirmation when running rm with *
setopt RM_STAR_WAIT # wait 10 seconds before accepting the rm * confirmation
