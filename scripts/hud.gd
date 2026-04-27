extends CanvasLayer

signal next_pressed

@onready var clue_label: Label = $Root/Top/ClueLabel
@onready var round_label: Label = $Root/Top/Header/RoundLabel
@onready var score_label: Label = $Root/Top/Header/ScoreLabel
@onready var result_label: Label = $Root/Bottom/ResultLabel
@onready var next_button: Button = $Root/Bottom/NextButton

func _ready() -> void:
	next_button.pressed.connect(func() -> void: next_pressed.emit())
	result_label.visible = false
	next_button.visible = false
	score_label.text = "Score: 0"

	var gm := get_parent()
	gm.round_started.connect(_on_round_started)
	gm.guess_resolved.connect(_on_guess_resolved)
	gm.game_over.connect(_on_game_over)

func _on_round_started(round_num: int, total_rounds: int, clue: String) -> void:
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
	clue_label.text = "Game Over"
	result_label.text = "Final score: %d" % final_score
	result_label.visible = true
	score_label.text = "Score: %d" % final_score
	next_button.text = "Play Again"
	next_button.visible = true
