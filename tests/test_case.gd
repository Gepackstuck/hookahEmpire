class_name TestCase
extends RefCounted
## Базовый класс тестов. Методы, начинающиеся с "test_", запускаются раннером.

var failures: Array[String] = []
var _current_test := ""


func begin(test_name: String) -> void:
	_current_test = test_name


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		failures.append("%s: ожидалось true. %s" % [_current_test, message])


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%s: ожидалось %s, получено %s. %s" % [_current_test, str(expected), str(actual), message])
