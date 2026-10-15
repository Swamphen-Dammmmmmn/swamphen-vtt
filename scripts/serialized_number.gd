extends RefCounted

# JSON numbers may be float even when the declared value is an integer.
# Match complete numeric values: never truncate a fractional input first.
static func is_one_of(value: Variant, accepted: Array) -> bool:
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT]: return false
	for expected: int in accepted:
		if float(value)==float(expected): return true
	return false
