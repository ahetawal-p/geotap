extends Node

signal location_tapped(latlon: Vector2, world_pos: Vector3)

@onready var globe_root: Node3D = get_node("../GlobeRoot")
@onready var camera: Camera3D = get_node("../Camera3D")
@onready var earth_body: StaticBody3D = get_node("../GlobeRoot/Globe/EarthBody")

const TAP_MOVE_THRESHOLD := 8.0
const TAP_TIME_THRESHOLD := 0.25
const DRAG_SENSITIVITY := 0.005
const PITCH_LIMIT := deg_to_rad(80.0)
const ZOOM_STEP := 0.25
const MIN_CAMERA_Z := 1.5
const MAX_CAMERA_Z := 4.0
const WHEEL_PAN_PIXELS := 25.0
const PAN_GESTURE_SCALE := 6.0

var _is_pressing := false
var _press_pos := Vector2.ZERO
var _press_time_s := 0.0
var _last_pos := Vector2.ZERO
var _moved_distance := 0.0
var _yaw := 0.0
var _pitch := 0.0

var _touches: Dictionary = {}
var _pinch_active := false
var _last_pinch_dist := -1.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 2:
				_pinch_active = true
				_last_pinch_dist = -1.0
				_is_pressing = false
		else:
			_touches.erase(event.index)
			if _touches.is_empty():
				_pinch_active = false
				_last_pinch_dist = -1.0
		return

	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _pinch_active:
			_handle_pinch()
		return

	if _pinch_active:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_press(event.position)
			else:
				_end_press(event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if event.ctrl_pressed:
				_zoom(-ZOOM_STEP)
			else:
				_apply_drag(Vector2(0, -WHEEL_PAN_PIXELS))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.ctrl_pressed:
				_zoom(ZOOM_STEP)
			else:
				_apply_drag(Vector2(0, WHEEL_PAN_PIXELS))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_apply_drag(Vector2(WHEEL_PAN_PIXELS, 0))
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_apply_drag(Vector2(-WHEEL_PAN_PIXELS, 0))
	elif event is InputEventPanGesture:
		_apply_drag(event.delta * PAN_GESTURE_SCALE)
	elif event is InputEventMagnifyGesture:
		if camera != null:
			camera.position.z = clamp(camera.position.z / event.factor, MIN_CAMERA_Z, MAX_CAMERA_Z)
	elif event is InputEventMouseMotion and _is_pressing:
		var delta: Vector2 = event.position - _last_pos
		_last_pos = event.position
		_moved_distance += delta.length()
		_apply_drag(delta)

func _handle_pinch() -> void:
	if _touches.size() < 2 or camera == null:
		return
	var positions: Array = _touches.values()
	var dist: float = (positions[0] as Vector2).distance_to(positions[1] as Vector2)
	if _last_pinch_dist > 0:
		var factor: float = dist / _last_pinch_dist
		camera.position.z = clamp(camera.position.z / factor, MIN_CAMERA_Z, MAX_CAMERA_Z)
	_last_pinch_dist = dist

func _zoom(delta: float) -> void:
	if camera == null:
		return
	camera.position.z = clamp(camera.position.z + delta, MIN_CAMERA_Z, MAX_CAMERA_Z)

func _begin_press(pos: Vector2) -> void:
	_is_pressing = true
	_press_pos = pos
	_last_pos = pos
	_press_time_s = Time.get_ticks_msec() / 1000.0
	_moved_distance = 0.0

func _end_press(pos: Vector2) -> void:
	if not _is_pressing:
		return
	_is_pressing = false
	var elapsed := Time.get_ticks_msec() / 1000.0 - _press_time_s
	if _moved_distance < TAP_MOVE_THRESHOLD and elapsed < TAP_TIME_THRESHOLD:
		_do_tap(pos)

func _apply_drag(delta: Vector2) -> void:
	_yaw += delta.x * DRAG_SENSITIVITY
	_pitch = clamp(_pitch + delta.y * DRAG_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_update_basis()

func _update_basis() -> void:
	# Pitch around world X applied AFTER yaw around world Y (yaw is the inner rotation).
	globe_root.basis = Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.UP, _yaw)

func _set_yaw(v: float) -> void:
	_yaw = v
	_update_basis()

func _set_pitch(v: float) -> void:
	_pitch = v
	_update_basis()

func animate_rotate_to_latlon(lat: float, lon: float, duration: float = 0.7) -> Tween:
	# Mesh+texture convention: target_yaw = PI - lon, target_pitch = lat (both in radians).
	var target_yaw: float = PI - deg_to_rad(lon)
	var target_pitch: float = clamp(deg_to_rad(lat), -PITCH_LIMIT, PITCH_LIMIT)
	# Pick shortest angular path for yaw (avoid wrapping the long way around).
	var diff: float = target_yaw - _yaw
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	target_yaw = _yaw + diff

	set_process_input(false)
	var tw: Tween = create_tween()
	tw.tween_method(_set_yaw, _yaw, target_yaw, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(_set_pitch, _pitch, target_pitch, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: set_process_input(true))
	return tw

func _do_tap(pos: Vector2) -> void:
	if camera == null or globe_root == null:
		return
	var from := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var to := from + dir * 100.0
	var space_state := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	if earth_body != null and result.collider != earth_body:
		return
	var local_hit: Vector3 = globe_root.to_local(result.position)
	var latlon := CoordUtils.point_to_latlon(local_hit)
	location_tapped.emit(latlon, result.position)
