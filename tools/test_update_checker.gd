extends SceneTree
## Sanity checks for the version helpers. Run:
##   godot --headless --path . --script tools/test_update_checker.gd

var _failures: int = 0


func _init() -> void:
	var checker: Node = load("res://scripts/systems/update_checker.gd").new()

	_expect_eq(checker.normalize_version("v0.2.0"), "0.2.0", "strip v prefix")
	_expect_eq(checker.normalize_version("release-1.4.2"), "1.4.2", "find digits in tag")
	_expect_eq(checker.read_version_file(), "0.1.0", "version.txt matches")

	_expect_true(checker.version_greater("0.2.0", "0.1.0"), "0.2.0 > 0.1.0")
	_expect_false(checker.version_greater("0.1.0", "0.1.0"), "equal is not greater")
	_expect_false(checker.version_greater("0.1.0", "0.2.0"), "older is not greater")
	_expect_true(checker.version_greater("0.1.10", "0.1.9"), "numeric, not string compare")
	_expect_true(checker.version_greater("1.0", "0.9.9"), "short version pads with zero")
	_expect_true(checker.version_greater("v0.2.0", "0.1.9"), "v-prefixed candidate")

	checker.free()
	if _failures == 0:
		print("UPDATE CHECKER TESTS: all passed")
	else:
		printerr("UPDATE CHECKER TESTS: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label, " (got ", actual, ", expected ", expected, ")")


func _expect_true(value: bool, label: String) -> void:
	_expect_eq(value, true, label)


func _expect_false(value: bool, label: String) -> void:
	_expect_eq(value, false, label)
