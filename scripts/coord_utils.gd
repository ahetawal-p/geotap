class_name CoordUtils
extends RefCounted

const EARTH_RADIUS_MI := 3958.8

# Godot's SphereMesh wraps the equirectangular texture with the prime meridian at -Z
# (not +Z), so we add a 180° offset to keep math and texture aligned.
const LON_OFFSET_DEG := 180.0

static func point_to_latlon(p_local: Vector3) -> Vector2:
	var n := p_local.normalized()
	var lat := rad_to_deg(asin(clamp(n.y, -1.0, 1.0)))
	var lon := rad_to_deg(atan2(n.x, n.z)) + LON_OFFSET_DEG
	if lon > 180.0:
		lon -= 360.0
	elif lon < -180.0:
		lon += 360.0
	return Vector2(lat, lon)

static func latlon_to_point(lat_deg: float, lon_deg: float, radius: float = 1.0) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg - LON_OFFSET_DEG)
	return Vector3(
		cos(lat) * sin(lon),
		sin(lat),
		cos(lat) * cos(lon)
	) * radius

static func haversine_mi(a: Vector2, b: Vector2) -> float:
	var lat1 := deg_to_rad(a.x)
	var lat2 := deg_to_rad(b.x)
	var dlat := lat2 - lat1
	var dlon := deg_to_rad(b.y - a.y)
	var h := sin(dlat * 0.5) ** 2 + cos(lat1) * cos(lat2) * sin(dlon * 0.5) ** 2
	return 2.0 * EARTH_RADIUS_MI * asin(sqrt(clamp(h, 0.0, 1.0)))
