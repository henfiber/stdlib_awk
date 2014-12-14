
#######################
### Version
#######################

# Returns the major or major.minor version of the invoked gawk
function my_version() {
	if (! "version" in PROCINFO) return "old"   # <= 3.0 - for 3.0 vs 2.1x consider making a test with IGNORECASE and regex matches
	if (PROCINFO["version"] ~ /^4/) {
		return ("identifiers" in PROCINFO) ? "4.1" : "4"
	} else 
		return "3.1"
}

#######################
###  Shell helpers  ###
#######################

function is_piped() {
	return !system("test -p /dev/fd/1 || test -p /dev/fd/2")  #[ ! -z "$PS1" ]
}

#######################
### Logging helpers ###
#######################

function message(msg, timestamp, pid) {
	if(timestamp)              msg = strftime("%F %R:%S") " " msg 
	if(pid && PROCINFO["pid"]) msg = PROCINFO["pid"] " " msg 
	printf "## %s\n", msg  > "/dev/stderr"
}

# Print an error message
function error(msg, timestamp, pid,   p) {
	p = is_piped()
	msg = (p) ? msg : ( "\33[01;31m" msg "\33[0m" )
	message(msg, timestamp, pid)
}




#######################
### File tests
#######################

# Check if file exists
function file_exists(file) {
    return !system("test -f " file)
}
# Check if file is readable
function isreadable(path) {
    return !system("test -r " quote(path))
}
# Check if directory exists
function dir_exists(file) {
    return !system("test -d " file)
}
# Detect whether a program exists in path
function command_exists(cmd, arg, checkOutput,    temp) {
	cmd = cmd " " arg " 2>/dev/null"
    if (checkOutput) {
        cmd | getline temp; close(cmd); return temp
    } else {
        return !system(cmd)
    }
}



######################
### Math functions ###
######################

function ceil(num) { if (num < 0) { return int(num) } else return int(num) + (num == int(num) ? 0 : 1) }



########################
### String functions ###
########################

# Remove leading and trailing white space
# gsub() is fast for prefix matches - consider changing the suffix case with str ~ /[[:blank:]]+$/
function strtrim(str) {
	gsub(/^[[:blank:]]+|[[:blank:]]+$/, "", str); return str
}

# Wrap an unquoted value using the specified quote (double quote the default)
# We use sub() instead of substring because it is faster when it fails early to match the prefix quote
function wrapquote(s, q) {
	if ( q == "" ) q = "\""
	if ( sub("^" q, "&", s) && sub(q "$", "&", s) && s != q ) return s
	return q s q
	# return ( substr(s, 1, 1) == q && substr(s, length(s)) == q ) ? s : q s q
}

# Removing the wrapping of the specified quote q (double quote the default)
# We use gsub for the opening quote test & removal, since it is faster than substr(s,1,1) especially when the test fails
# the first time substr is run in an unknown string, it computes the string length which takes time, then it is very fast
# We could use match() but match() is slower than substr() when the test for the opening quote succeeds
function unwrapquote(s, q) {
	if ( q == "" ) q = "\""
	if ( sub("^" q, "", s) ) return ( sub(q "$", "", s) ) ? s : q s  # if there is an opening but not a closing quote, put the opening quote back
	return s
	# return ( substr(s, 1, 1) != q || substr(s, length(s)) != q ) ? s : substr(s, 2, length(s) - 2)
}





##########################
### Arrays
##########################

# Join elements of a single-dimensional number-indexed array (such as those computed by split()) into a string
# A : the input array, s = sep, stard/end : specify a range of array elements to use for the string join
function implode(A, s, start, end,   RET,len,i) {
	len = length(A); if(! len) return ""
	if (start == "" || start < 1) start = 1
	if (end   == "" || end > len) end = len
	if (! (start in A) || ! (end in A)) return ""    # make a check this is a sequential number-indexed array
	RET = A[start]; i = start
	while (i < end) { 
		RET = RET s A[++i]
	}
	return RET
}


# Like split() but save the segments to keys rather than values
function split_to_keys(str, Arr, sep,   Tmp,i) {
	split(str, Tmp, sep)
	for (i = length(Tmp); i >= 1 ; i--) {
		Arr[Tmp[i]] = i  #; delete Tmp[i]
	}
}





##########################
### Running commands
##########################

# Suitably escape single quotes in a system command
function shell_quote(s,   SINGLE, QSINGLE, i, X, n, RET) {
	# gsub(/'/, "'\\''", s); # return "'" s "'"	
    if (s == "") return "\"\""
    SINGLE = "\047"  # single quote # x27
    QSINGLE = "\"\047\""

    n = split(s, X, SINGLE)

    RET = SINGLE X[1] SINGLE
    for (i = 2; i <= n; i++)
        RET = RET QSINGLE SINGLE X[i] SINGLE
    return RET
}



# Run and capture the result of the command cmd in one shot
# What RS? "^$" is the fastest - "\n$" will skip the last trailing line 
# otherwise use something that may not occur in the cmd output like "_\\f_" (more portable but less robust)
# Set trim_last_nl to 0, to disable trimming the last line
# How to get exit code of command? Some ideas here http://stackoverflow.com/q/21296859/1305020
function capture_cmd(cmd, trim_last_nl, noClose,  output,ecode,save_rs) {
	if( !cmd ) return
	if( trim_last_nl != "0" ) trim_last_nl = 1
	
	# Set RS after saving previous value
	save_rs = RS; RS = "^$"  # "^$" is the fastest - "\n$" will skip the last trailing line
	
	# Running the command after resetting ERRNO - then close the pipe
	ERRNO = 0
    ecode = (cmd | getline output)
    if ( ecode < 0 || ERRNO ) {
		error("error " ERRNO " when capturing cmd " cmd)
	}
    if ( !noClose ) close(cmd)
    if ( ERRNO )  	error("Error: " ERRNO " when closing cmd " cmd)
	
	# Trim trailing line
	if (trim_last_nl && RS != "\n$") {
		sub(/\n$/, "", output)
	}
	
	# Restore RS and return
	RS = save_rs
    return (match(output, /^[[:blank:]]*$/)) ? "" : output
}


# Pipe text to cmd, as a coproc, and capture the full output at once
function capture_coproc(text, cmd, trim_last_nl,   output,save_rs) {
	if(!cmd) return
	if(trim_last_nl != "0") trim_last_nl = 1
	
	# Set RS after saving previous value
	save_rs = RS; RS = "^$"  # "^$" is the fastest - "\n$" will skip the last trailing line
	
	# Running the command after resetting ERRNO - then close the pipe
	ERRNO = 0
	
	print text |& cmd
	close(cmd, "to")
	text="" 			# save some memory on long input
	cmd |& getline output
	fflush("")
	close(cmd)
    if(ERRNO)
		error("Error: " ERRNO " when capturing pipe " cmd)
	
	# Trim trailing line
	if (trim_last_nl && RS != "\n$") {
		sub(/\n$/, "", output)
	}
	
	# Restore RS and return
	RS = save_rs
    return output
}


# Make temp file with trap to remove the file - using a non-closing pipe
function mktemp(ftype, prefix,   cmd,template,v) {
	cmd = "mktemp"
	if (ftype == "dir")  
		cmd = "mktemp -d"
	else if (ftype == "pipe") 
		cmd = "mkfifo"

	if (prefix == "") 
		prefix = "${TMPDIR:-/tmp}/awk"
	
	cmd = "T=$(mktemp -u \"" prefix ".XXXXXX\"); " cmd " \"$T\" || exit 1; trap \"rm -f '$T'\" 0 1 2 3 15; printf '%s\n' \"$T\"; cat /dev/zero"
    if ((cmd | getline v) > 0) {
        return v
    } else {
        return ""
    }
}

# Make a temporary pipe instead of a regular file
function mkpipe(prefix,   cmd,v) {
	if (prefix == "") 
		prefix = "${TMPDIR:-/tmp}/awk.pipe"	
	return mktemp( "pipe", prefix )
}



################################
### Command wrappers - curl, jq
################################

# Get the result of an http(s) call
# TODO: Maybe url_encode() the url
BEGIN { CURL_BIN = "curl" }
function curl(url, body, content_type, timeout,   ret, cmd) {
	if (!url) error("Not enough arguments to curl")
	if (timeout == "") timeout = 45
	if (content_type == "") content_type = "application/json"
	
	cmd = (CURL_BIN) ? CURL_BIN : "curl"
	if (content_type == "NULL") {
		return system(sprintf("%s -s -S -k -m %s %s", cmd, timeout, wrapquote(url)))
	} else if (body == "") {
		ret = capture_cmd(sprintf("%s -s -S -k -m %s -H %s %s", 
						  cmd, timeout, wrapquote("Content-Type: " content_type), wrapquote(url)) )
	} else {
		ret = capture_cmd(sprintf("%s -s -S -k -m %s -H %s -d %s %s", 
						  cmd, timeout, wrapquote("Content-Type: " content_type), shell_quote(body), wrapquote(url)) )	
	}
	return ret
}



# jq wrapper - run as a coprocess to process 'text' and return output
function with_jq(text, expr, pretty, no_raw,   cmd,RET) {
	cmd = "jq"
	if (text == "") return ""
	if (! pretty) cmd = cmd " -c"
	if (! no_raw) cmd = cmd " -r"
	RET = capture_coproc(text, cmd " " shell_quote(expr))
	return RET
}





##########################
### Date-Time functions 
##########################



# Get a milliseconds precision timestamp using GNU date
function systime_msec(   cmd,cur) { 
	cmd="date \"+%s.%N\""; cmd | getline cur; close(cmd); return cur 
}



# Add seconds (%s) and nanoseconds (%N) support to strftime()
function strftime_extended(fmt, t, flag_utc,    sec,msec) {
	sec = t; msec = "000000000"
	if (RSTART = index(t, ".")) {
		sec = substr(t, 1, RSTART-1)
		msec = substr(t, RSTART+1)
	}
	gsub(/%s/, sec, fmt)
	if ( msec ) gsub(/%N/, msec, fmt)
	return strftime(fmt, t)
}



# Validate that the argument is a proper timestamp
function validate_timestamp(t) { 
	return (length(t) >= 10 && t ~ /^[0-9]+[.]?[0-9]+$/) 
}



# expands a shorthand expression like "1h" into "1 hours" - signs (+/-) are preserved as a prefix
function expand_rel_time(abbr, Ret,   sign,value,unit,unit_expanded) {
	sub(" ", "", abbr) # remove spaces
	if (abbr ~ /^[+-]/) { 
		sign = substr(abbr, 1, 1)
		abbr = substr(abbr, 2) 
	}
	if ( match(abbr, /^[0-9]+[.]?[0-9]*/) > 0 ) {
		unit  = substr(abbr, RLENGTH+1)
		value = substr(abbr, 1, RLENGTH)+0
	} else {
		unit  = abbr; value = 1
	}
	
	# We cannot use tolower(unit) since the same letter "m" is used for both minutes and Months
	unit_expanded = ""
	     if (unit == "m")     { unit_expanded = "minutes" }
	else if (unit ~ /h|H/)    { unit_expanded = "hours" }
	else if (unit ~ /^(s|S)/) { unit_expanded = "seconds" }
	else if (unit ~ /ms|MS/)  { unit_expanded = "milliseconds" }
	else if (unit ~ /d|D/)    { unit_expanded = "days" }	
	else if (unit == "M")     { unit_expanded = "months" }	
	else if (unit ~ /y|Y/)    { unit_expanded = "years" }	
	else if (unit ~ /w|W/)    { unit_expanded = "weeks" }	
	else if (unit ~ /ns|NS/)  { unit_expanded = "nanoseconds" }
	else 
		error("time unit \"" unit "\" not supported")

	Ret["value"] = value; Ret["unit"] = unit; Ret["unit_expanded"] = unit_expanded; Ret["sign"] = sign
	return (sign value " " unit_expanded)
}



# Round a timestamp in whole units
function round_timestamp(abbr, now,   now_spec,week_day,Pos,Now,First,Max,anchor,i) {
	expand_rel_time(abbr, Ret)
	unit = Ret["unit"]; value = Ret["value"]
	
	if ( unit !~ /^(y|Y|M|m|d|D|h|H|s|S|ms|MS|ns|NS|w|W)$/ )
		error("time unit " unit " not supported")	
	
	if (unit ~ /w|W/) {
		week_day = strftime("%w", now)
		if (week_day > 0) now -= week_day * 86400
		unit = "d"
	}
	
	# Compute the time spec as required by mktime (YYYY MM DD HH MM SS) - also suitable for use in split()
	now_spec = strftime_extended("%Y %m %d %H %M %S %N", now)
	
	# Parse datespec - "year Month day hour mins secs nanosecs"
	split(now_spec, Now, " ")
	
	# Create a hash of units with positions in the datetime string
	Pos["y"]  = 1; Pos["Y"]  = 1; Pos["M"] = 2;  Pos["d"] = 3;  Pos["D"] = 3
	Pos["h"]  = 4; Pos["H"]  = 4; Pos["m"] = 5;  Pos["s"] = 6;  Pos["S"] = 6
	Pos["ms"] = 7; Pos["MS"] = 7; Pos["ns"] = 7; Pos["NS"] = 7
	
	split("1970 01 01 00 00 00 000", First, " ") 	# Create an ordered array of units with the starting value for each unit
	split("0 12 31 12 60 60 1000", Max, " ") 		# Create an ordered array of units with the max value for each unit
	
	# Quantize the trailing units after unit
	anchor = Pos[unit]
	for (i = anchor+1; i <= length(Now); i++) 
		Now[i] = First[i]
	if (unit ~ /ms|MS/) Now[7] = int(Now[7]/1000000)
	# If a value is provided, then round also this time unit (except from days which cannot be consistently rounded) in whole multiples of the value
	if (value > 1 && unit !~ /d|D/ && (Max[anchor] % value) == 0) {  
		Now[anchor] = int((Now[anchor] - First[anchor]) / value) * value + First[anchor]
	}
	if (unit ~ /ms|MS/) Now[7] = sprintf("%03d", Now[7])  # force 3 decimal places prepended with 0 if needed
	
	# Now rebuild the timestamp
	now_spec = Now[1]; for (i=2; i <= length(Now); i++) now_spec = now_spec " " Now[i]
	return (mktime(substr(now_spec, 1, 19)) "." substr(now_spec, 21))
}



# Shift the timestamp according to "expr" (e.g. -1 hours) using GNU date
function systime_shift(expr, t,   t_rfc3339,cmd,cur) {
	t_rfc3339 = strftime_extended("%Y-%m-%d %H:%M:%S.%N%z", t)
	cmd="date --date=\"" t_rfc3339 " " expr "\" \"+%s.%N\""
	cmd | getline cur; close(cmd)
	return cur
}

# Wrapper around systime_shift() after first expanding the abbreviated expression (e.g. -1h), and handling edge cases
function compute_relative(abbr, now,   ret,secs) {
	if (!now) now = systime_msec()

	expand_rel_time(abbr, Ret)
	unit = Ret["unit"]; value = Ret["value"]; unit_expanded = Ret["unit_expanded"]; sign = Ret["sign"]	
	
	if ( unit ~ /^(y|Y|M|w|W)$/ ) {
		ret = systime_shift(sign value " " unit_expanded, now)
	} else {
		     if (unit == "m")     { secs = 60.0 }
		else if (unit ~ /ms|MS/)  { secs = 0.001 }
		else if (unit ~ /^(s|S)/) { secs = 1.0 }
		else if (unit ~ /h|H/)    { secs = 3600.0 }
		else if (unit ~ /d|D/)    { secs = 86400.0 }
		else if (unit ~ /ns|NS/)  { secs = 0.000000001 }
		
		ret = (sign == "-") ? (now - secs * value) : (now + secs * value)
		ret = sprintf("%.3f", ret)
	}
	return ret
}


# add or subtract a tiny fraction (microsecond) from the resulting timestamp
function exclude_timestamp(t, open) {
	if (open ~ /l/)  # l / left
		return sprintf("%.9f", t + 0.000001)
	else
		return sprintf("%.9f", t - 0.000001)
}

#####################
### Configuration ###
#####################

# Reads .ini file inifile and fills array Result. 
# If you want to read only a specific section, set "section_filter" as "~ your_regex" (without //) or directly "your_regex"
# If you want to filter out specific sections, set "section_filter" as "!~your_regex"
# The sections and keys are combined in the array index : section.key1, section.key2 etc. according to "sep"
function read_inifile(inifile, Result, section_filter, sep,   _line,Sections,section,name,value,idx) {
	if (sep == "") sep = SUBSEP
	if (section_filter) {
		if (! match(section_filter, /~/)) {
			section_filter_op = "~"
			section_filter_regex = section_filter
		} else {
			section_filter_op    = strtrim(substr(section_filter, 1, RSTART))
			section_filter_regex = strtrim(substr(section_filter, RSTART+1))
		}
	}
	
	while (getline _line < inifile) {
		sub(/^[[:space:]]*[;#].*$/, "", _line)
		sub(/[;#][^"']*$/, "", _line)
		sub(/^[[:space:]]+/, "", _line)
		sub(/[[:space:]]+$/, "", _line)

		if (_line == "")
			continue

		# Parsing section - i.e. [section-name]
		if (_line ~ /^\[.+\]$/) {
			section = substr(_line, 2, length(_line)-2)
			if (section in Sections) {
				error("Duplicate section \"" section "\" detected in " inifile ". Aborting.");
				exit 7
			}
			Sections[section] = 1
			continue
		}

		if(section_filter) {
			if (section_filter_op == "~"  && section !~ section_filter_regex) continue
			if (section_filter_op == "!~" && section  ~ section_filter_regex) continue
		}		

		# Parsing name and value
		idx = match(_line, /=/)
		if (idx <= 0) continue  # ignore lines without an "="

		name  = strtrim(substr(_line, 1, idx-1))
		value = strtrim(substr(_line, idx+1))

		# In case the value is quoted
		if (value ~ /^".*"$/ || value ~ /^'.*'$/){
			Result[section sep name] = substr(value, 2, length(value)-2)
			continue
		}

		# Not properly quoted values
		if (value ~ /^[\"\']|[\"\']$/)
			continue

		# squeeze to single space when value is unquoted
		gsub(/[ \t][ \t]+/, " ", value)  
		
		# Add it to the Result array
		Result[section sep name] = value
	}
	close(inifile)
}


