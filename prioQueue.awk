# @(#) PrioQueue 1.0.2 2016-11-15
# 2016-11-15 Slight modifications by Ilias Kotinas (henfiber@gmail.com)

# TODO (Ilias)
# 	Make PrioInsert() faster for large queues with randomly distributed priorities


# Priority Queue Routines

## Data structures:
# In order to allow multiple instance of identical elements, elements are
# stored using a pseudo-index (pindex), a unique integer value.
# Queue["last"] is the last pindex used.
# Queue["num"] is the number of elements in the queue.
# Queue["lowest"] is the pindex of the lowest-valued element in the queue.
# Queue["highest"] is the pindex of the highest-valued element in the queue.
# Each priority queue element has this structure:
# Queue[n,"gt"] = pindex of element with next greater value
# Queue[n,"lt"] = pindex of element with next lower value
# Queue[n,"val"] = value of this element
# Queue[n,"data"] = data associated with the element, if any

## Public functions

# Insert: Insert an element with given value at a point in a priority queue
# such that its value appears in order with the other elements in the queue.
# Queue[] is the queue to insert into.
# Value is the value of the element.
# Data is an optional string associated with Value.
# Return value: number of elements in the queue after insertion.
function PrioInsert(Queue,Value,Data,
		pi,cind,nl,lind,gind,ind) {
    ind = GetFreePindex(Queue)
    Queue[ind,"val"] = Value
    Queue[ind,"data"] = Data
    if (!Queue["num"])	# Empty queue
		Queue["lowest"] = Queue["highest"] = ind
    else if (Value <= Queue[lind = Queue["lowest"],"val"]) {
		Queue[ind,"gt"] = lind
		Queue[lind,"lt"] = ind
		Queue["lowest"] = ind
    } else if (Value >= Queue[gind = Queue["highest"],"val"]) {
		Queue[ind,"lt"] = gind
		Queue[gind,"gt"] = ind
		Queue["highest"] = ind
    } else  {
		cind = Queue["lowest"]
		while (Queue[cind,"val"] < Value)
			cind = Queue[cind,"gt"]
		# Queue[cind] now has a value >= element to be inserted, so insert element between it and the next-lowest valued element.
		# The cases where insert-element has the same or lower/higher value than the end elements has been dealt with, so we
		# know this element is being inserted between two elements.
		nl = Queue[cind,"lt"]
		Queue[nl,"gt"] = ind
		Queue[ind,"lt"] = nl
		Queue[ind,"gt"] = cind
		Queue[cind,"lt"] = ind
    }
    return ++Queue["num"]
}

# PopLow(), PopHigh():
# Returns the value and data of the lowest/highest-value element of Queue
# in Data["val"] and Data["data"], and removes that element from the queue.
# Return value:
# The number of elements in the queue *before* the element is removed.
# If the queue was empty, 0 is returned and no data is stored in Data[].
# On error, -1 is returned.  This indicates a corrupt queue.
function PopLow(Queue,Data) {
	return PrioPop(Queue,Data,"lowest","gt","lt")
}

function PopHigh(Queue,Data) {
	return PrioPop(Queue,Data,"highest","lt","gt")
}

# PeekLow(), PeekHigh():
# Returns the value and data of the lowest/highest-value element of Queue
# in Data["val"] and Data["data"]
# Return value:
# The number of elements in the queue.
# If 0 is returned, there will be no data in Data[].
# On error, -1 is returned.  This indicates a corrupt queue.
function PeekLow(Queue,Data) {
	return PrioPeek(Queue,Data,"lowest")
}

function PeekHigh(Queue,Data) {
	return PrioPeek(Queue,Data,"highest")
}

## Private functions

# Get a free pindex.
# Maintains Queue["last"]
function GetFreePindex(Queue,
		ind) {
	ind = Queue["last"]+1
	while ((ind,"val") in Queue)
		ind++
	Queue["last"] = ind
	return ind
}

function PrioPeek(Queue,Data,end,
		ind) {
	if (!Queue["num"])
		return 0
	if (!(end in Queue))
		return -1
	ind = Queue[end]
	if (!((ind,"val") in Queue))
		return -1
	Data["val"] = Queue[ind,"val"]
	Data["data"] = Queue[ind,"data"]
	return Queue["num"]
}

function PrioPop(Queue,Data,end,indir,outdir,
		ind,nx,num) {
	if ((num = PrioPeek(Queue,Data,end)) <= 0)
		return num
	ind = Queue[end]
	if (num > 1) {
		if (!((ind,indir) in Queue))
			return -1
		nx = Queue[ind,indir]
		Queue[end] = nx
		delete Queue[nx,outdir]
	}
	delete Queue[ind,"val"]
	delete Queue[ind,"data"]
	delete Queue[ind,indir]

	return Queue["num"]--
}

# For debugging - printed from lowest to highest
function DumpPrioQueue(Queue,   elem,e) {
	if (!Queue["num"])
		return -1
	ind = Queue["lowest"]
	while (1) {
		printf "%s = %s, ", ind "$val",  Queue[ind, "val"]
		printf "%s = %s\n", ind "$data", Queue[ind, "data"]
		if (((ind, "gt") in Queue))
			ind = Queue[ind, "gt"]
		else
			break
	}
	printf "\n"
}


