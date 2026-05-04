class_name Locations
extends RefCounted

const DATA_PATH := "res://data/locations.json"

static func pick_round(n: int, region: String = "World") -> Array:
	var text := FileAccess.get_file_as_string(DATA_PATH)
	if text.is_empty():
		push_error("Failed to read %s" % DATA_PATH)
		return []
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		push_error("locations.json did not parse to an Array")
		return []
	var arr: Array = (parsed as Array).duplicate()
	if region != "World":
		arr = arr.filter(func(loc: Variant) -> bool:
			return loc is Dictionary and loc.get("region", "") == region
		)
	arr.shuffle()
	return arr.slice(0, min(n, arr.size()))
