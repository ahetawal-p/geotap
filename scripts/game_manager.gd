extends Node3D

signal round_started(round_num: int, total_rounds: int, clue: String)
signal guess_resolved(distance_mi: float, round_score: int, total_score: int, is_last_round: bool)
signal game_over(final_score: int)

const TOTAL_ROUNDS := 5

const MARKER_SURFACE_OFFSET := 1.03
const MARKER_DROP_HEIGHT := 1.30
const DROP_DURATION := 0.45
const LABEL_SCREEN_DOWN_OFFSET := 0.018

const NOMINATIM_URL := "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&lat=%f&lon=%f"

const GUESS_LABEL_BASE_PIXEL_SIZE := 0.0006
const TARGET_LABEL_BASE_PIXEL_SIZE := 0.0009

const LINE_THRESHOLD_MI := 1000.0
const LINE_RADIUS := 1.045
const LINE_SEGMENTS := 40
const LINE_THICKNESS := 0.012

@onready var globe_controller: Node = $GlobeController
@onready var globe_root: Node3D = $GlobeRoot
@onready var camera: Camera3D = $Camera3D
@onready var guess_marker: MeshInstance3D = $GlobeRoot/GuessMarker
@onready var target_marker: MeshInstance3D = $GlobeRoot/TargetMarker
@onready var hud: CanvasLayer = $HUD
@onready var world_env: WorldEnvironment = $WorldEnvironment

const BASE_CAMERA_Z := 2.5

var _guess_label: Label3D
var _target_label: Label3D
var _connection_line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _geocode_request: HTTPRequest
var _round_active := false
var _current_round := 0
var _total_score := 0
var _round_targets: Array = []
var _awaiting_play_again := false

func _ready() -> void:
	guess_marker.visible = false
	target_marker.visible = false
	guess_marker.material_override = _make_marker_material(Color(0.95, 0.2, 0.2))
	target_marker.material_override = _make_marker_material(Color(0.2, 0.85, 0.3))
	globe_controller.location_tapped.connect(_on_location_tapped)
	hud.next_pressed.connect(_on_next_pressed)

	_guess_label = _make_billboard_label(GUESS_LABEL_BASE_PIXEL_SIZE)
	_target_label = _make_billboard_label(TARGET_LABEL_BASE_PIXEL_SIZE)
	globe_root.add_child(_guess_label)
	globe_root.add_child(_target_label)

	_line_mesh = ImmediateMesh.new()
	_connection_line = MeshInstance3D.new()
	_connection_line.mesh = _line_mesh
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(1.0, 0.85, 0.3)
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_connection_line.material_override = line_mat
	_connection_line.visible = false
	globe_root.add_child(_connection_line)

	_geocode_request = HTTPRequest.new()
	add_child(_geocode_request)
	_geocode_request.request_completed.connect(_on_geocode_completed)

	get_tree().root.size_changed.connect(_adjust_for_viewport)
	# Wait one frame so the actual canvas/window size is settled (mobile web in particular).
	await get_tree().process_frame
	_adjust_for_viewport()

	_start_game()

func _adjust_for_viewport() -> void:
	_adjust_ui_scale()
	_adjust_camera_for_aspect()

func _adjust_camera_for_aspect() -> void:
	var win_size := get_window().size
	if win_size.x <= 0 or win_size.y <= 0:
		return
	var aspect: float = float(win_size.x) / float(win_size.y)
	var target_z: float = BASE_CAMERA_Z
	if aspect < 1.0:
		target_z = BASE_CAMERA_Z / aspect
	camera.position.z = clamp(target_z, 1.5, 6.0)

func _adjust_ui_scale() -> void:
	var win := get_window()
	var min_dim: int = mini(win.size.x, win.size.y)
	var scale: float = 1.0
	if min_dim < 500:
		scale = 2.5
	elif min_dim < 750:
		scale = 1.5
	win.content_scale_factor = scale
	if _guess_label != null:
		_guess_label.pixel_size = GUESS_LABEL_BASE_PIXEL_SIZE * scale
	if _target_label != null:
		_target_label.pixel_size = TARGET_LABEL_BASE_PIXEL_SIZE * scale

func _make_billboard_label(pixel_size: float) -> Label3D:
	var lbl := Label3D.new()
	lbl.font_size = 48
	lbl.outline_size = 12
	lbl.modulate = Color.WHITE
	lbl.outline_modulate = Color.BLACK
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = pixel_size
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.visible = false
	return lbl

func _start_game() -> void:
	_round_targets = Locations.pick_round(TOTAL_ROUNDS)
	if _round_targets.size() < TOTAL_ROUNDS:
		push_error("Not enough locations to start the game")
		return
	_current_round = 0
	_total_score = 0
	_awaiting_play_again = false
	_start_round()

func _start_round() -> void:
	_round_active = true
	guess_marker.visible = false
	target_marker.visible = false
	_guess_label.visible = false
	_target_label.visible = false
	_connection_line.visible = false
	var loc: Dictionary = _round_targets[_current_round]
	var clue: String = loc.get("clue", loc.name)
	print("Round %d/%d target: %s (%.4f, %.4f)" % [_current_round + 1, TOTAL_ROUNDS, loc.name, loc.lat, loc.lon])
	round_started.emit(_current_round + 1, TOTAL_ROUNDS, clue)

func _on_next_pressed() -> void:
	if _awaiting_play_again:
		_start_game()
		return

	_current_round += 1
	if _current_round >= TOTAL_ROUNDS:
		_awaiting_play_again = true
		game_over.emit(_total_score)
	else:
		_start_round()

func _make_marker_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat

func _on_location_tapped(latlon: Vector2, world_pos: Vector3) -> void:
	if not _round_active:
		return
	_round_active = false

	var loc: Dictionary = _round_targets[_current_round]
	var target_lat: float = loc.lat
	var target_lon: float = loc.lon

	var guess_dir: Vector3 = globe_root.to_local(world_pos).normalized()
	var target_dir := CoordUtils.latlon_to_point(target_lat, target_lon)
	var dist := CoordUtils.haversine_mi(latlon, Vector2(target_lat, target_lon))
	var score: int = int(round(max(0.0, 5000.0 - dist * 0.7242)))
	_total_score += score
	print("Guess: (%.2f, %.2f)  Distance: %.0f mi  Score: %d  Total: %d" % [latlon.x, latlon.y, dist, score, _total_score])

	_guess_label.text = "..."
	_target_label.text = loc.name

	_request_reverse_geocode(latlon.x, latlon.y)

	var dist_local := dist
	var score_local := score
	var total_local := _total_score
	var is_last := _current_round == TOTAL_ROUNDS - 1

	_drop_marker(guess_marker, guess_dir, func() -> void:
		_position_label_below(_guess_label, guess_marker)
		_guess_label.visible = true
		# Globe rotation, line draw, and target-marker drop all run in parallel.
		_drop_marker(target_marker, target_dir, func() -> void:
			_position_label_below(_target_label, target_marker)
			_target_label.visible = true
		)
		if dist_local > LINE_THRESHOLD_MI:
			_animate_arc_draw(guess_dir, target_dir, 2.2)
		var rot_tw: Tween = globe_controller.animate_rotate_to_latlon(target_lat, target_lon, 2.2)
		rot_tw.finished.connect(func() -> void:
			guess_resolved.emit(dist_local, score_local, total_local, is_last)
		)
	)

func _animate_arc_draw(from_dir: Vector3, to_dir: Vector3, duration: float) -> void:
	_line_mesh.clear_surfaces()
	_connection_line.visible = true
	var tw := create_tween()
	tw.tween_method(
		func(p: float) -> void:
			_build_great_circle_partial(from_dir, to_dir, p),
		0.0, 1.0, duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _build_great_circle_partial(from_dir: Vector3, to_dir: Vector3, progress: float) -> void:
	_line_mesh.clear_surfaces()
	progress = clamp(progress, 0.0, 1.0)
	if progress < 0.001:
		return
	var dp: float = clamp(from_dir.dot(to_dir), -1.0, 1.0)
	var omega: float = acos(dp)
	var sin_om: float = sin(omega)
	if sin_om < 0.0001:
		return

	var n_segs: int = max(2, int(round(LINE_SEGMENTS * progress)))
	var points: Array[Vector3] = []
	for i in range(n_segs + 1):
		var t: float = (float(i) / float(n_segs)) * progress
		var p: Vector3 = (sin((1.0 - t) * omega) * from_dir + sin(t * omega) * to_dir) / sin_om
		points.append(p.normalized() * LINE_RADIUS)

	_line_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var half_w: float = LINE_THICKNESS * 0.5
	for i in range(points.size()):
		var p: Vector3 = points[i]
		var radial: Vector3 = p.normalized()
		var tangent: Vector3
		if i == 0:
			tangent = (points[i + 1] - p).normalized()
		elif i == points.size() - 1:
			tangent = (p - points[i - 1]).normalized()
		else:
			tangent = (points[i + 1] - points[i - 1]).normalized()
		var right: Vector3 = tangent.cross(radial).normalized()
		_line_mesh.surface_add_vertex(p - right * half_w)
		_line_mesh.surface_add_vertex(p + right * half_w)
	_line_mesh.surface_end()

func _position_label_below(label: Label3D, marker: Node3D) -> void:
	var cam := get_viewport().get_camera_3d()
	var screen_down := Vector3.DOWN
	if cam != null:
		screen_down = -cam.global_transform.basis.y
	label.global_position = marker.global_position + screen_down * LABEL_SCREEN_DOWN_OFFSET

func _process(_delta: float) -> void:
	if world_env != null and world_env.environment != null:
		world_env.environment.sky_rotation = globe_root.rotation
	if _guess_label.visible:
		_position_label_below(_guess_label, guess_marker)
	if _target_label.visible:
		_position_label_below(_target_label, target_marker)

func _request_reverse_geocode(lat: float, lon: float) -> void:
	var url := NOMINATIM_URL % [lat, lon]
	var headers := PackedStringArray(["User-Agent: Geotap/1.0", "Accept-Language: en"])
	var err := _geocode_request.request(url, headers)
	if err != OK:
		_guess_label.text = "Unknown"

func _on_geocode_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200:
		_guess_label.text = "Unknown"
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		_guess_label.text = "Unknown"
		return
	_guess_label.text = _format_place_name(data)

func _format_place_name(data: Dictionary) -> String:
	var addr: Dictionary = data.get("address", {})
	var place: String = addr.get("city", "")
	if place == "":
		place = addr.get("town", "")
	if place == "":
		place = addr.get("village", "")
	if place == "":
		place = addr.get("state", "")
	var country: String = addr.get("country", "")
	if place != "" and country != "":
		return "%s, %s" % [place, country]
	if country != "":
		return country
	var fallback: String = data.get("display_name", "Unknown")
	if fallback.length() > 40:
		fallback = fallback.substr(0, 40) + "..."
	return fallback

func _drop_marker(marker: MeshInstance3D, surface_dir: Vector3, on_finish: Callable) -> void:
	marker.position = surface_dir * MARKER_DROP_HEIGHT
	marker.visible = true
	var tw := create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(marker, "position", surface_dir * MARKER_SURFACE_OFFSET, DROP_DURATION)
	if on_finish.is_valid():
		tw.finished.connect(on_finish)
