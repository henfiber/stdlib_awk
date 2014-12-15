#!/bin/bash
#-----------

LIB_AWK="@include ../scheduler.awk; "

### Scheduler tests

	# Sleep until time has passed beyond timestamp $1
	function _sleep_until_portable() {
		[ -z "$1" ] && _error "_sleep_until_portable requires a timestamp to be provided as a 1st argument"
		
		awk -v target="$1" "$LIB_AWK"'
			BEGIN {
				if (! validate_timestamp(target)) { error("invalid timestamp: \"" target "\""); exit 2; }
				while (1) {
					diff = ceil(target - systime_msec())  # we use ceil() for integer-only capable "sleep" command
					if ( diff <= 0 ) exit 0
					if (system(sprintf("trap \"exit 1\" 2; sleep %d", diff)) != 0) exit 1  # Allow interrupts
				}
			}
		'
	}
	
	
	# Instead of using system sleep, we use the PROCINFO["/some/input", "READ_TIMEOUT"] millisecond read-timeout support by GAWK
	# Why use this function? Because shell does not support floating point arithmetic so we would need to invoke a subshell for computing fractional seconds
	function sleep_until() {
		[ -z "$1" ] && _error "sleep_until() requires a timestamp to be provided as a 1st argument"
		_command_exists 'gawk' || _sleep_until_portable "$@"
		
		gawk -v target="$1" "$LIB_AWK"'
			BEGIN {
				if (! validate_timestamp(target)) { error("invalid timestamp: \"" target "\""); exit 2; }
				sleep_until(target)
			}
		'
	}
			
	# run every 5 seconds - 500th millisecond
	# run every minute - 30th second
	# run every hour - 30th minute etc.
	function repeat_every() {
		local abbr=$1
		task="printf 'now\n'" # date '+%s.%N' &
		echo "now is: $(date '+%s.%N')"
		while [ -n 1 ]; do
			now=$(date "+%s.%N")
			next=$(gawk -v abbr="${abbr}" -v now="$now" "$LIB_AWK"'BEGIN { print compute_relative("+" abbr, round_timestamp(abbr, now)) }')
			sleep_until "$next"
			eval "$task" # | date -f- '+%s.%N'
		done
	}



	# Scheduler
		# definitions : run every X, this
		# start: getall_next and add_to_queue
		# loop:  find_next; wait_next; fork_next; compute_next and add_to_queue
	# Performance : On complete system starvation (128 cpu hogs) it performs good for intervals over 20 milliseconds
	function minicron() {
		local abbr1=$1; local abbr2=$2; local abbr3=$3; local method=${4:-callback}
		echo "now is: $(date '+%s.%N')"
		printf "%s\n%s\n%s" "$abbr1" "$abbr2" "$abbr3" | gawk -v method=$method "$LIB_AWK"'
			function task_run(i, now, Info) {
				print "Running task " i " at: " now > "/dev/stderr"
			}
			NF { Defs[++ind_def] = $0; Info[ind_def]["none"] = 1 }
			
			END {
				minicron(Defs, Info, method, "task_run")
			}
		'
	}



### RUN helper

	# Running a function as a "command" - Check if it exists first
	function run() {
		if [ ! -z "$1" ]; then
			func="$1"; shift;
			[ "$func" = 'run' ] && return 1
			local arg args
			while [ $# -gt 0 ]; do   #while [ ! -z "$1" ]; do
				arg="${1//\$/\\\$}" # escape dollar before eval
				arg="${1//\"/\\\"}" # escape double-quotes before eval
				args="$args \"$arg\""
				shift
			done
			if declare -f -F $func >/dev/null 2>&1; then #check function exists
				eval "$func $args"
			else
				echo "Command/Choice '$func' does not exist"
			fi
		fi
	}






