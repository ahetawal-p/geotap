extends CanvasLayer

signal next_pressed
signal round_count_selected(count: int)

@onready var clue_label: Label = $Root/Top/ClueLabel
@onready var round_label: Label = $Root/Top/Header/RoundLabel
@onready var score_label: Label = $Root/Top/Header/ScoreLabel
@onready var result_label: Label = $Root/Bottom/ResultLabel
@onready var next_button: Button = $Root/Bottom/NextButton

@onready var top_container: VBoxContainer = $Root/Top
@onready var bottom_container: VBoxContainer = $Root/Bottom
@onready var round_picker: VBoxContainer = $Root/RoundPicker
@onready var picker_title: Label = $Root/RoundPicker/Title
@onready var picker_subtitle: Label = $Root/RoundPicker/Subtitle

func _ready() -> void:
	next_button.pressed.connect(func() -> void: next_pressed.emit())
	$Root/RoundPicker/Btn5.pressed.connect(func() -> void: round_count_selected.emit(5))
	$Root/RoundPicker/Btn10.pressed.connect(func() -> void: round_count_selected.emit(10))
	$Root/RoundPicker/Btn20.pressed.connect(func() -> void: round_count_selected.emit(20))

	# Initial state: picker visible, gameplay HUD hidden.
	_show_initial_picker()

	var gm := get_parent()
	gm.round_started.connect(_on_round_started)
	gm.guess_resolved.connect(_on_guess_resolved)
	gm.game_over.connect(_on_game_over)

func _show_initial_picker() -> void:
	picker_title.text = "How many rounds?"
	picker_subtitle.visible = false
	round_picker.visible = true
	top_container.visible = false
	bottom_container.visible = false
	result_label.visible = false
	next_button.visible = false
	score_label.text = "Score: 0"

func _on_round_started(round_num: int, total_rounds: int, clue: String) -> void:
	round_picker.visible = false
	top_container.visible = true
	bottom_container.visible = true
	round_label.text = "Round %d/%d" % [round_num, total_rounds]
	clue_label.text = "Find: %s" % clue
	result_label.visible = false
	next_button.visible = false

func _on_guess_resolved(distance_mi: float, round_score: int, total_score: int, is_last_round: bool) -> void:
	score_label.text = "Score: %d" % total_score
	result_label.text = "%.0f mi away   +%d" % [distance_mi, round_score]
	result_label.visible = true
	next_button.text = "See results" if is_last_round else "Next >"
	next_button.visible = true

func _on_game_over(final_score: int) -> void:
	picker_title.text = "Final Score: %d" % final_score
	picker_subtitle.text = "Play again — how many rounds?"
	picker_subtitle.visible = true
	round_picker.visible = true
	top_container.visible = false
	bottom_container.visible = false
	result_label.visible = false
	next_button.visible = false
