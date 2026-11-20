extends Node

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _run() -> void:
	var old_difficulty: int = GameSettings.minigame_difficulty
	var old_bots: int = GameSettings.effective_bot_count()
	var old_host: bool = Network.is_host
	var old_client: bool = Network.is_client
	Network.is_host = false
	Network.is_client = true
	Network._net_session_config(GameSettings.GAME_MINIGAMES, true, 3, "meadow",
		"shopping_cart", {}, Network.EVENT_RACE, Network.RACE_SCENE, "", false,
		{}, false, 2)
	_check(Network.bot_difficulty() == 2, "Host difficulty was not replicated")
	GameSettings.set_ai_difficulty(0)
	_check(Network.bot_difficulty() == 2, "Client local setting overrode host difficulty")
	Network._net_session_config(GameSettings.GAME_MINIGAMES, true, 99, "not-a-map",
		"shopping_cart", {}, Network.EVENT_RACE, Network.RACE_SCENE, "", false,
		{}, false, 99)
	_check(Network.session_bot_count == Network.MAX_BOT_COUNT, "Bot count was not bounded")
	_check(Network.bot_difficulty() == 2, "Difficulty was not bounded")
	_check(Network.session_map_id != "not-a-map", "Unsafe map id was accepted")

	var cargo: Node = load("res://scripts/minigames/cargo_rush.gd").new()
	var knockout: Node = load("res://scripts/minigames/knockout.gd").new()
	var bomb: Node = load("res://scripts/minigames/bomb_tag.gd").new()
	var race: Node = load("res://scripts/minigames/grass_race.gd").new()
	for mode in [cargo, knockout, bomb, race]:
		mode.set("_multiplayer", true)
		mode.set("_selftest", false)
	Network.session_bots = false
	Network.session_bot_count = 5
	_check(cargo.call("_bot_count") == 0, "Deliver ignored disabled bots")
	_check(knockout.call("_desired_bot_count") == 0, "Knockout ignored disabled bots")
	_check(bomb.call("_bot_count") == 0, "Blast Tag ignored disabled bots")
	_check(race.call("_bot_count") == 0, "Race ignored disabled bots")
	Network.session_bots = true
	Network.session_bot_count = 3
	_check(cargo.call("_bot_count") == 3, "Deliver did not use host bot count")
	_check(knockout.call("_desired_bot_count") == 3, "Knockout did not use host bot count")
	_check(bomb.call("_bot_count") == 3, "Blast Tag did not use host bot count")
	_check(race.call("_bot_count") == 3, "Race did not use host bot count")
	for mode in [cargo, knockout, bomb, race]:
		mode.free()

	Network.is_host = old_host
	Network.is_client = old_client
	GameSettings.set_ai_difficulty(old_difficulty)
	GameSettings.set_bot_total(old_bots)
	print("MODE_RULES_SMOKE: %s" % ("PASS" if _failures == 0 else "%d failures" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
