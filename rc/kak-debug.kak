# This option indicates the kak-debug source directory.
declare-option -hidden str debug_dir %sh{echo $(dirname $kak_source)/../}
# This option indicates the arguments passed to the kak-debug server.
declare-option -hidden str debug_args ""
# This option dictates the command run to run the kak-debug binary.
#declare-option -hidden str debug_cmd "poetry run python %opt{debug_dir}/src/main.py -s %val{session}"
# This option indicates whether the kak-debug server for this session is running.
declare-option -hidden bool debug_running false
# This option contains the path of the kak-debug socket for this session.
declare-option -hidden str debug_socket ""

# This option indicates the client in which the "stacktrace" buffer will be shown
declare-option str stacktraceclient

# This option indicates the client in which the "variables" buffer will be shown
declare-option str variablesclient

set-face global DapBreakpoint red,default
set-face global DapLocation blue,default

declare-option str debug_breakpoint_active_symbol "●"
declare-option str debug_location_symbol "➡"

# Contains all line breakpoints in this format
# line|file line|file line|file ...
declare-option -hidden str-list debug_breakpoints_info
# If execution is currently stopped, shows the current location in this format
# line|file
declare-option -hidden str debug_location_info

declare-option -hidden line-specs debug_breakpoints_flags
declare-option -hidden line-specs debug_location_flags
declare-option -hidden int debug_variables_cursor_line
# Initial setting to ensure cursor is set to top
set-option global debug_variables_cursor_line 1

add-highlighter shared/debug group -passes move
add-highlighter shared/debug/ flag-lines DapLocation debug_location_flags
add-highlighter shared/debug/ flag-lines DapBreakpoint debug_breakpoints_flags

hook global WinDisplay .* %{
    try %{
        add-highlighter window/debug-ref ref -passes move debug
    }
    debug-refresh-breakpoints-flags %val{buffile}
    debug-refresh-location-flag %val{buffile}
}

hook global BufOpenFile .* %{
    debug-refresh-breakpoints-flags %val{buffile}
    debug-refresh-location-flag %val{buffile}
}

define-command -hidden debug-setup-ui-tmux %{
    # Setup the jump client
    rename-client main
    set-option global jumpclient main

    # Setup the stacktrace client
    tmux-terminal-vertical kak -c %val{session} -e "rename-client stacktrace"
    set-option global stacktraceclient stacktrace

    # Setup the variables client
    tmux-terminal-horizontal kak -c %val{session} -e "rename-client variables"
    set-option global variablesclient variables
}

define-command -hidden debug-setup-ui-wezterm %{
    # Setup the jump client
    rename-client main
    set-option global jumpclient main

    # Setup the stacktrace client
    wezterm-terminal-vertical kak -c %val{session} -e "rename-client stacktrace"
    set-option global stacktraceclient stacktrace

    # Setup the variables client
    wezterm-terminal-horizontal kak -c %val{session} -e "rename-client variables"
    set-option global variablesclient variables
}

define-command -hidden debug-setup-ui-default %{
    # Setup the jump client
    rename-client main
    set global jumpclient main
    
    # Setup the stacktrace client
    new rename-client stacktrace
    set global stacktraceclient stacktrace

    # Setup the variables client
    new rename-client variables
    set global variablesclient variables
}

define-command debug-setup-ui %{
    evaluate-commands %sh{
        # Determine which windowing system is in use,
        # and choose the correct one to setup our layout with.
        if [ -n "$TMUX" ]; then
            printf "%s\n" "debug-setup-ui-tmux"
        elif [ -n "$WEZTERM_PANE" ]; then
            printf "%s\n" "debug-setup-ui-wezterm"
        else
            printf "%s\n" "debug-setup-ui-default"
        fi
    }
}

define-command debug-takedown-ui %{
    # Kill the stacktrace client
    evaluate-commands -try-client %opt{stacktraceclient} %{
        quit!
    }
    # Kill the variables client
    evaluate-commands -try-client %opt{variablesclient} %{
        quit!
    }
}

define-command debug-start %{
    eval %sh{
        # kak_opt_debug_breakpoints_info
        # kak_buffile
        if [ "$kak_opt_debug_running" = false ]; then
            # Setup the UI
            printf "%s\n" "debug-setup-ui"

            #printf "echo -debug %s\n" "%opt{debug_cmd}"
            # Start the kak-debug binary
            (eval "poetry run python $kak_opt_debug_dir/src/main.py -s $kak_session $kak_opt_debug_args") > /dev/null 2>&1 < /dev/null &
        else
            printf "echo %s\n" "kak-debug already running"
        fi
    }
}

define-command debug-stop %{
    # Stop the kak-debug binary
    nop %sh{
        printf '{
        "cmd": "stop"
        }' > $kak_opt_debug_socket
    }
}

define-command debug-set-breakpoint -params 2 %{
    set-option -add global debug_breakpoints_info "%arg{1}|%arg{2}"
    debug-refresh-breakpoints-flags %arg{2}
}

define-command debug-clear-breakpoint -params 2 %{
    set-option -remove global debug_breakpoints_info "%arg{1}|%arg{2}"
    debug-refresh-breakpoints-flags %arg{2}
}

define-command debug-toggle-breakpoint %{ eval %sh{
    if [ "$kak_opt_debug_running" = false ]; then
        # Go through every existing breakpoint
        for current in $kak_opt_debug_breakpoints_info; do
            buffer=${current#*|*}
            line=${current%%|*}

            # If the current file and cursor line match this currently existing breakpoint
            if [ "$buffer" = "$kak_buffile" ] && [ "$line" = "$kak_cursor_line" ]; then
                printf "set-option -remove global debug_breakpoints_info '%s|%s'\n" "$line" "$buffer"
                printf "debug-refresh-breakpoints-flags %s\n" "$buffer"
                exit
            fi
        done
        # If we're here, we don't have this breakpoint yet
        printf "set-option -add global debug_breakpoints_info '%s|%s'\n" "$kak_cursor_line" "$kak_buffile"
        printf "debug-refresh-breakpoints-flags %s\n" "$kak_buffile"
    else
        printf "echo %s\n" "Can't toggle breakpoints while running"
    fi
}}

#
# Commands sent directly to debug adebugter
#

define-command debug-continue %{ eval %sh{
    if [ "$kak_opt_debug_running" = false ]; then
        printf "%s\n" "debug-start"
    else
        printf '{
        "cmd": "continue" 
        }' > $kak_opt_debug_socket
    fi
}}

define-command debug-next %{ nop %sh{
    printf '{
    "cmd": "next" 
    }' > $kak_opt_debug_socket
}}

define-command debug-step-in %{ nop %sh{
    printf '{
    "cmd": "stepIn" 
    }' > $kak_opt_debug_socket
}}

define-command debug-step-out %{ nop %sh{
    printf '{
    "cmd": "stepOut" 
    }' > $kak_opt_debug_socket
}}

define-command debug-evaluate -params 1 %{ nop %sh{
    printf '{
    "cmd": "evaluate",
    "args": {
    "expression": "%s"
    }
    }' "$1" > $kak_opt_debug_socket
}}

#
# Misc commands called by kak-debug server
#

define-command debug-select-config -params 2.. %{
    evaluate-commands %sh{
        command="menu "
        for config in "$@"; do
            command=$command"$config "
            config_cmd=$(printf '{"cmd": "select-config", "args": {"config": "%s"}}' "$config")
            printf "%s\n" "echo -debug $config_cmd"
            command=$command"%{ nop %sh{ printf '%s' '$config_cmd' > $kak_opt_debug_socket } } "
        done
        printf "%s\n" "$command"
    }
}

define-command debug-set-location -params 2 %{
    set-option global debug_location_info "%arg{1}|%arg{2}"
    try %{ eval -client %opt{jumpclient} debug-refresh-location-flag %arg{2} }
}

define-command debug-reset-location %{
    set-option global debug_location_info ""
    try %{ eval -client %opt{jumpclient} debug-refresh-location-flag %val{buffile} }
}

define-command debug-jump-to-location %{
    try %{ eval %sh{
        # Get the current location info
        eval set -- "$kak_quoted_opt_debug_location_info"
        [ $# -eq 0 ] && exit
        # Extract the line and buffer
        line="${1%%|*}"
        buffer="${1#*|*}"
        # Edit the file at the given line, failing if it doesn't exist (it should be open already, fingers crossed)
        printf "edit -existing '%s' %s; exec gi" "$buffer" "$line"
    }}
}

define-command -hidden -params 1 debug-refresh-breakpoints-flags %{
    try %{
        set-option "buffer=%arg{1}" debug_breakpoints_flags %val{timestamp}
        eval %sh{
            # Loop through all the current breakpoints
            for current in $kak_opt_debug_breakpoints_info; do
                buffer=${current#*|*}
                # If the current buffer is correct
                if [ "$buffer" = "$1" ]; then
                    line=${current%%|*}
            	    # Set the breakpoint flag
                    printf "set-option -add \"buffer=%s\" debug_breakpoints_flags %s|$kak_opt_debug_breakpoint_active_symbol\n" "$buffer" "$line"
                fi
            done
        }
    }
}

define-command -hidden -params 1 debug-refresh-location-flag %{
    try %{
        set-option global debug_location_flags %val{timestamp}
        set-option "buffer=%arg{1}" debug_location_flags %val{timestamp}
        eval %sh{
            current=$kak_opt_debug_location_info
            buffer=${current#*|*}
            # If the current buffer is correct
            if [ "$buffer" = "$1" ]; then
                line=${current%%|*}
                # Set the location flag
                printf "set-option -add \"buffer=%s\" debug_location_flags %s|$kak_opt_debug_location_symbol\n" "$buffer" "$line"
            fi
        }
    }
}

#
# Handle the variable/stacktrace buffers
#

define-command -hidden debug-show-stacktrace -params 1 %{
    # Show the stack trace in the stack trace buffer
    evaluate-commands -save-regs '"' -try-client %opt[stacktraceclient] %{
        edit! -scratch *stacktrace*
        set-register '"' %arg{1}
        execute-keys Pgg
    }
}

define-command -hidden debug-show-variables -params 1 %{
    evaluate-commands -save-regs '"' -try-client %opt[variablesclient] %{
        edit! -scratch *variables*
        set-register '"' %arg{1}
        execute-keys "P%opt{debug_variables_cursor_line}g"
        map buffer normal '<ret>' ':<space>debug-expand-variable<ret>'
        # Reset to ensure default value, will be set by expand-variable
        set-option global debug_variables_cursor_line 1

        # strings, keep first
        add-highlighter buffer/vals regions
        add-highlighter buffer/vals/double_string region '"'  (?<!\\)(\\\\)*" fill string
        add-highlighter buffer/vals/single_string region "'"  (?<!\\)(\\\\)*' fill string
        # Scope and varialbe lines
        add-highlighter buffer/scope regex "^(Scope):\s([\w\s]+)" 2:attribute
        add-highlighter buffer/variable_line regex "^\s+([+|-]\s)?(<\d+>)\s([^\s]+)\s\(([A-Za-z]+)\)" 2:comment 3:variable 4:type
        # values
        add-highlighter buffer/type_num regex "(-?\d+)$" 1:value
        add-highlighter buffer/type_bool regex "((?i)true|false)$" 0:value
        add-highlighter buffer/type_null regex "((?i)null|nil|undefined)$" 0:keyword
        add-highlighter buffer/type_array regex "(array\(\d+\))$" 0:default+i
    }
}

define-command -hidden debug-expand-variable %{
    evaluate-commands -try-client %opt{variablesclient} %{
        # Send current line to kak-debug to expand
        set-option global debug_variables_cursor_line %val{cursor_line}
        nop %sh{
            value="${kak_opt_debug_variables_cursor_line}"
            printf '{
            "cmd": "expand",
            "args": {
            "line": "%s"
            }
            }' $value > $kak_opt_debug_socket
        }
    }
}

#
# Responses to reverseRequests
#

define-command -hidden debug-run-in-terminal-tmux -params 1.. %{
    evaluate-commands -try-client %opt{stacktraceclient} %{
        tmux-terminal-horizontal %arg{@}
    }
}

define-command -hidden debug-run-in-terminal-wezterm -params 1.. %{
    evaluate-commands -try-client %opt{stacktraceclient} %{
        wezterm-terminal-horizontal %arg{@}
    }
}

define-command -hidden debug-run-in-terminal-default -params 1.. %{
    terminal %arg{@}
}

define-command -hidden debug-run-in-terminal -params 1.. %{
    evaluate-commands %sh{
        # Determine which windowing system is in use,
        # and choose the correct one.
        if [ -n "$TMUX" ]; then
            printf "%s %s\n" "debug-run-in-terminal-tmux" "$*"
        elif [ -n "$WEZTERM_PANE" ]; then
            printf "%s %s\n" "debug-run-in-terminal-wezterm" "$*"
        else
            printf "%s %s\n" "debug-run-in-terminal-default" "$*"
        fi
    }
    nop %sh{
        printf '{
        "cmd": "pid"
        }' > $kak_opt_debug_socket
    }
}

#
# Responses to debug adebugter responses
#

define-command -hidden debug-output -params 2 %{
    evaluate-commands -client %opt{jumpclient} %{
        echo -debug DAP ADAPTER %arg{1}: %arg{2}
    }
}

define-command -hidden debug-stack-trace -params 3 %{
    debug-set-location %arg{1} %arg{2}
    try %{ eval -client %opt{jumpclient} debug-jump-to-location }
    debug-show-stacktrace %arg{3}
}

define-command -hidden debug-evaluate-response -params 2.. %{
    try %{ eval -client %opt{jumpclient} %{ info -title "Result" " %arg{1}:%arg{2} "}}
}
