
# system sleep command
function _sleep_sys(seconds) { if (system(sprintf("trap \"exit 1\" 2; sleep %.3f", seconds)) != 0) exit 1 }


# gawk-native sleep implementation
# A gawk 4 extension is also available that provides fractional sleep seconds support and fractional gettimeofday()
#	- see: https://www.gnu.org/software/gawk/manual/html_node/Extension-Sample-Time.html#Extension-Sample-Time
#	- @load "time"
#	- the_time = gettimeofday()
#	- result = sleep(seconds) 	# seconds can be floating point
# alternatives for dev_block : a stalled pipe "/tmp/mypipe" made with mkfifo, "/inet/udp/0/127.0.0.1/0" (faster than localhost), "/dev/stderr", "/dev/fd/3"
function sleep(seconds,   dev_block,dev_null) { 
	
	if ( (seconds+0) < 0.001 ) return 0  # this prevents most of bad input (negative, zero, lower-than-millesecond, and string arguments)
	
	dev_block="/inet/udp/0/127.0.0.1/0"  # alternative: dev_block="/dev/stderr"
	
	# setting READ_TIMEOUT on this input will set ERRNO - not need to wait for getline
	ERRNO = 0;  PROCINFO[dev_block, "READ_TIMEOUT"] = (seconds * 1000)    # timeout in milliseconds
	
	# If there is an error - use the system sleep command
	if (ERRNO || PROCINFO["version"] !~ /^4/) {  # in case that fails or not supported use system sleep
		_sleep_sys(seconds)
	} else {
		getline dev_null < dev_block;  close(dev_block)		# we use the dummy var "dev_null" to avoid setting $0
	}
	return 1
}


# Helper to sleep until specific timestamp
function sleep_until(target,   diff,use_msec) {
	#if (target ~ /[0-9]+[.][0-9]+$/) use_msec = 1
	diff = target - systime_msec()
	if ( diff <= 0 ) return 0  			# return fail (0) if target has already passed
	while (1) {
		if ( diff <= 0 ) return 1
		if ( diff > 10 ) { sleep(diff/2) } else { sleep(diff) }  # wake up early on long idle periods to make for timer drifts (on high system load)
		diff = target - systime_msec()  # diff = (use_msec) ? (target - systime_msec()) : (target - systime())
	}
	return 1
}

# Compute the immediate next timestamp when given an interval and an offset
function compute_next(expr, tstamp,    pos, period, offset, tnext) {
	period = expr; offset = ""
	if (pos = index(expr, ":")) {
		period = substr(expr, 1,  pos - 1)
		offset = substr(expr, pos + 1)
	}
	tnext = round_timestamp(period, tstamp)
	if (offset)
		tnext = compute_relative("+" offset, tnext)
	if ((tnext + 0) <= (tstamp + 1))   # make sure a string timestamp like "1491234567.000" is converted to numeric or else bad things happen
		tnext = compute_relative("+" period, tnext)
	return tnext
}

# Task Scheduler
function minicron(Tasks, TasksInfo, method, handler,   
				TasksQueue, TasksNext, Data, now, now_scheduled, tnext, got_rest, cnt_unrest,
				task_id, i, n, expr, now_cnt) {
	split("", TasksNext)
	
	# Initialize Queue
	split("", TasksQueue)
	now = systime_msec()
	
	# Start: Find the next time instance for all definitions and add them to the queue
	for (task_id = 1; task_id <= length(Tasks); task_id++) { 
		expr = Tasks[task_id]
		tnext = compute_next(expr, now)
		PrioInsert(TasksQueue, tnext, task_id) 
	}
	
	if (method == "debug") {
		DumpPrioQueue(TasksQueue)
	}
	
	while(1) {
		now_cnt = 0
		if(n = PopLow(TasksQueue, Data)) {
			tnext = Data["val"]
			TasksNext[++now_cnt] = Data["data"]
		}
		
		split("", Data)
		while(n > 1 && TasksQueue[TasksQueue["lowest"], "val"] == tnext) {
			n = PopLow(TasksQueue, Data)
			TasksNext[++now_cnt] = Data["data"]
		}
		
		# Get some sleep and check whether the time has already passed
		got_rest = sleep_until(tnext)
		
		if(!got_rest) {
			if (++cnt_unrest > 3) {
				error("Multiple consecutive past timestamps coming in scheduler. That indicates a bug, an unsupported time utility or invalid input. Forcing some sleep..")
				sleep(cnt_unrest - 2)
			}
		} else {
			cnt_unrest = 0
		}
		
		# Needed timestamps and some checks
		now = systime_msec() 
		now_scheduled = tnext
		
		# Now take some action
		for (i=1; i <= now_cnt; i++) {
			task_id = TasksNext[i]
			expr = Tasks[task_id]
			tnext = compute_next(expr, now)
			PrioInsert(TasksQueue, tnext, task_id)
			if (method == "callback") {
				# @handler(task_id, now_scheduled, TasksInfo)  # commented-out for gawk3 support
				task_handler(task_id, now_scheduled, TasksInfo)
			} else if (method == "program") {
				system(sprintf("%s %s %s %s", handler, task_id, now_scheduled, TasksInfo))
			} else if (method == "debug") {
				message("Running task " task_id " at: " now " - next is: " tnext)
			}
		}
		split("", TasksNext)
		split("", Data)
	}
}



# The same Scheduler as before, only this case cheating the clock
# This function nevers call the real clock, it only pretends that it did by sleeping just some seconds
# and assuming that the time is equal to that of the first scheduled task
function cheatycron(Tasks, TasksInfo, method, handler, time_start,  
				TasksQueue, TasksNext, Data, now, now_scheduled, tnext, got_rest, cnt_unrest,
				task_id, i, n, expr, now_cnt) {
	split("", TasksNext)
	
	# Initialize Queue
	split("", TasksQueue)
	now = (time_start) ? time_start : compute_relative("-25h", round_timestamp("1d", systime_msec()))
	
	# Start: Find the next time instance for all definitions and add them to the queue
	for (task_id = 1; task_id <= length(Tasks); task_id++) { 
		expr = Tasks[task_id]
		tnext = compute_next(expr, now)
		PrioInsert(TasksQueue, tnext, task_id) 
	}
	
	if (method == "debug") {
		DumpPrioQueue(TasksQueue)
	}
	
	while(1) {
		now_cnt = 0
		if(n = PopLow(TasksQueue, Data)) {
			tnext = Data["val"]
			TasksNext[++now_cnt] = Data["data"]
		}
		
		split("", Data)
		while(n > 1 && TasksQueue[TasksQueue["lowest"], "val"] == tnext) {
			n = PopLow(TasksQueue, Data)
			TasksNext[++now_cnt] = Data["data"]
		}
		
		# Needed timestamps and some checks
		now = tnext
		now_scheduled = tnext
		
		# Exit if you reached the present
		if ((now + 0) >= (systime_msec() + 0)) {
			message("The queue scheduler finished his job. Reached present. Exiting", 1)
			exit
		}
		
		# Now take some action
		for (i=1; i <= now_cnt; i++) {
			task_id = TasksNext[i]
			expr = Tasks[task_id]
			tnext = compute_next(expr, now)
			PrioInsert(TasksQueue, tnext, task_id)
			message("Running task " task_id " at: " now " - next is: " tnext)
			if (method == "callback") {
				# @handler(task_id, now_scheduled, TasksInfo)  # commented-out for gawk3 support
				task_handler(task_id, now_scheduled, TasksInfo)
			} else if (method == "program") {
				system(sprintf("%s %s %s %s", handler, task_id, now_scheduled, TasksInfo))
			} else if (method == "debug") {
				message("Running task " task_id " at: " now " - next is: " tnext)
			}
		}
		split("", TasksNext)
		split("", Data)
		
		# Get some sleep
		_sleep_sys(4)
	}
}


