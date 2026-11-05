extends Control
## Minigames hub prototype: Free Play (solo cards + options) and Tournament.
## No minigame is wired yet; every PLAY/START button is disabled on purpose.

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"

const MINIGAMES: Array[Dictionary] = [
	{
		"id": "slalom",
		"name": "CONE SLALOM",
		"desc": "Weave through the cone lane as fast as you can without clipping a cone. Solo.",
	},
	{
		"id": "crates",
		"name": "CRATE SMASH",
		"desc": "Shatter the crate wall in as few hits as possible. Solo.",
	},
	{
		"id": "drift",
		"name": "DRIFT SCORE",
		"desc": "Chain drifts around the ring and bank the highest score before time runs out. Solo.",
	},
	{
		"id": "boost",
		"name": "BOOST RUN",
		"desc": "Hit every boost pad down the straight and finish under the target time. Solo.",
	},
]

const DIFFICULTIES: PackedStringArray = ["EASY", "NORMAL", "HARD"]
const ROUND_OPTIONS: Array[int] = [3, 5, 7]

@onready var _free_tab: Button = %FreePlayTab
@onready var _tour_tab: Button = %TournamentTab
@onready var _free_box: VBoxContainer = %FreeBox
@onready var _tour_box: VBoxContainer = %TournamentBox
@onready var _card_list: VBoxContainer = %CardList
@onready var _detail_name: Label = %DetailName
@onready var _detail_desc: Label = %DetailDesc
@onready var _play_button: Button = %PlayButton
@onready var _difficulty_option: OptionButton = %DifficultyOption
@onready var _rounds_option: OptionButton = %RoundsOption
@onready var _vehicle_option: OptionButton = %VehicleOption
@onready var _tour_rounds_option: OptionButton = %TourRoundsOption
@onready var _tour_difficulty_option: OptionButton = %TourDifficultyOption
@onready var _tour_vehicle_option: OptionButton = %TourVehicleOption
@onready var _back_button: Button = %BackButton

var _cards: Array[Button] = []
var _selected: int = 0


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_free_tab.pressed.connect(_show_tab.bind(0))
	_tour_tab.pressed.connect(_show_tab.bind(1))
	_back_button.pressed.connect(_on_back)
	_build_cards()
	_build_options()
	_select(0)
	_show_tab(0)


func _build_cards() -> void:
	for index in MINIGAMES.size():
		var button := Button.new()
		button.text = "%s      SOLO      SOON" % str(MINIGAMES[index]["name"])
		button.custom_minimum_size = Vector2(0, 54)
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(_select.bind(index))
		var script: Script = load("res://scripts/ui/candy_button.gd")
		button.set_script(script)
		_card_list.add_child(button)
		_cards.append(button)


func _build_options() -> void:
	for name: String in DIFFICULTIES:
		_difficulty_option.add_item(name)
	for rounds: int in ROUND_OPTIONS:
		_rounds_option.add_item("%d ROUNDS" % rounds)
		_tour_rounds_option.add_item("%d MINIGAMES" % rounds)
	for difficulty: String in DIFFICULTIES:
		_tour_difficulty_option.add_item(difficulty)
	for entry: Dictionary in Catalog.all():
		var label: String = str(entry.get("name", entry.get("id", "?")))
		_vehicle_option.add_item(label)
		_tour_vehicle_option.add_item(label)

	_difficulty_option.selected = clampi(GameSettings.minigame_difficulty, 0, 2)
	_tour_difficulty_option.selected = clampi(GameSettings.minigame_difficulty, 0, 2)
	var rounds_index: int = ROUND_OPTIONS.find(GameSettings.minigame_rounds)
	_rounds_option.selected = rounds_index if rounds_index >= 0 else 0
	_tour_rounds_option.selected = rounds_index if rounds_index >= 0 else 0
	var vehicle_index: int = Catalog.index_of(GameSettings.minigame_vehicle)
	_vehicle_option.selected = vehicle_index
	_tour_vehicle_option.selected = vehicle_index

	_difficulty_option.item_selected.connect(_save_options)
	_rounds_option.item_selected.connect(_save_options)
	_vehicle_option.item_selected.connect(_save_options)
	_tour_difficulty_option.item_selected.connect(_save_options)
	_tour_rounds_option.item_selected.connect(_save_options)
	_tour_vehicle_option.item_selected.connect(_save_options)


func _save_options(_index: int = 0) -> void:
	var vehicle: String = str(Catalog.all()[_vehicle_option.selected].get("id", "shopping_cart"))
	GameSettings.set_minigame_options(_difficulty_option.selected,
		ROUND_OPTIONS[_rounds_option.selected], vehicle)


func _select(index: int) -> void:
	_selected = index
	var data: Dictionary = MINIGAMES[index]
	_detail_name.text = str(data["name"])
	_detail_desc.text = str(data["desc"])
	for card_index in _cards.size():
		_cards[card_index].fill_color = Color("ffd22e") if card_index == index else Color("b9b2c9")


func _show_tab(tab: int) -> void:
	_free_box.visible = tab == 0
	_tour_box.visible = tab == 1
	_free_tab.fill_color = Color("ffd22e") if tab == 0 else Color("b9b2c9")
	_tour_tab.fill_color = Color("ffd22e") if tab == 1 else Color("b9b2c9")


func _on_back() -> void:
	SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY MENU")
