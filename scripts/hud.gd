extends CanvasLayer

signal next_pressed
signal round_count_selected(count: int)
signal region_selected(region: String)
signal restart_pressed

const REGION_PLACEHOLDER := "Choose a Region"

const REGIONS: Array[String] = [
	"Whole World",
	"North America",
	"South America",
	"Europe",
	"Africa",
	"Asia",
	"Oceania",
	"Antarctica",
]

@onready var clue_label: Label = $Root/Top/ClueLabel
@onready var round_label: Label = $Root/Top/Header/RoundLabel
@onready var score_label: Label = $Root/Top/Header/ScoreLabel
@onready var result_label: Label = $Root/Bottom/ResultLabel
@onready var next_button: Button = $Root/Bottom/NextButton

@onready var top_container: VBoxContainer = $Root/Top
@onready var bottom_container: VBoxContainer = $Root/Bottom

@onready var region_picker: VBoxContainer = $Root/RegionPicker
@onready var region_title: Label = $Root/RegionPicker/Title
@onready var region_dropdown: OptionButton = $Root/RegionPicker/RegionDropdown

@onready var round_picker: VBoxContainer = $Root/RoundPicker
@onready var round_title: Label = $Root/RoundPicker/HeaderRow/Title
@onready var back_button: Button = $Root/RoundPicker/HeaderRow/BackButton

@onready var restart_button: Button = $Root/RestartButton
@onready var restart_confirm: ConfirmationDialog = $Root/RestartConfirm

func _ready() -> void:
	region_dropdown.add_item(REGION_PLACEHOLDER)
	for region in REGIONS:
		region_dropdown.add_item(region)
	region_dropdown.selected = 0

	next_button.pressed.connect(func() -> void: next_pressed.emit())
	$Root/RoundPicker/Btn5.pressed.connect(func() -> void: round_count_selected.emit(5))
	$Root/RoundPicker/Btn10.pressed.connect(func() -> void: round_count_selected.emit(10))
	$Root/RoundPicker/Btn20.pressed.connect(func() -> void: round_count_selected.emit(20))
	back_button.pressed.connect(_on_back_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)

	# Region dropdown auto-advances to round picker on item pick.
	# Use the popup's index_pressed so re-picking the same region still advances.
	region_dropdown.get_popup().index_pressed.connect(_on_region_dropdown_picked)

	restart_confirm.confirmed.connect(_on_restart_confirmed)

	# Initial state: region picker first, then round picker, then gameplay HUD.
	_show_region_picker()

	var gm := get_parent()
	gm.round_started.connect(_on_round_started)
	gm.guess_resolved.connect(_on_guess_resolved)
	gm.game_over.connect(_on_game_over)

func _show_region_picker() -> void:
	region_title.text = ""
	region_title.visible = false
	region_dropdown.selected = 0
	region_picker.visible = true
	round_picker.visible = false
	top_container.visible = false
	bottom_container.visible = false
	result_label.visible = false
	next_button.visible = false
	restart_button.visible = false
	score_label.text = "Score: 0"

func _show_round_picker() -> void:
	round_title.text = "Choose Rounds"
	round_picker.visible = true
	region_picker.visible = false
	top_container.visible = false
	bottom_container.visible = false
	result_label.visible = false
	next_button.visible = false
	restart_button.visible = false

func _on_region_dropdown_picked(index: int) -> void:
	if index == 0:
		# Placeholder re-selected; stay put.
		return
	region_dropdown.selected = index
	region_selected.emit(REGIONS[index - 1])
	_show_round_picker()

func _on_back_pressed() -> void:
	_show_region_picker()

func _on_restart_button_pressed() -> void:
	restart_confirm.popup_centered()

func _on_restart_confirmed() -> void:
	restart_pressed.emit()
	_show_region_picker()

func _on_round_started(round_num: int, total_rounds: int, clue: String) -> void:
	round_picker.visible = false
	region_picker.visible = false
	top_container.visible = true
	bottom_container.visible = true
	round_label.text = "Round %d/%d" % [round_num, total_rounds]
	clue_label.text = "Find: %s" % clue
	result_label.visible = false
	next_button.visible = false
	restart_button.visible = true

func _on_guess_resolved(distance_mi: float, round_score: int, total_score: int, is_last_round: bool) -> void:
	score_label.text = "Score: %d" % total_score
	result_label.text = "%.0f mi away   +%d" % [distance_mi, round_score]
	result_label.visible = true
	next_button.text = "See results" if is_last_round else "Next >"
	next_button.visible = true

func _on_game_over(final_score: int) -> void:
	region_title.text = "Final Score: %d" % final_score
	region_title.visible = true
	region_dropdown.selected = 0
	region_picker.visible = true
	round_picker.visible = false
	top_container.visible = false
	bottom_container.visible = false
	result_label.visible = false
	next_button.visible = false
	restart_button.visible = false
