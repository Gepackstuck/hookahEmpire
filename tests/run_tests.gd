extends SceneTree
## Запуск: godot --headless --path <проект> --script res://tests/run_tests.gd
## Тесты могут использовать await (например, ждать кадр, чтобы сработал _ready у нод).
## Находит tests/unit/test_*.gd, выполняет все методы test_*, выходит с кодом 0/1.

const UNIT_DIR := "res://tests/unit"


func _initialize() -> void:
	var total := 0
	var failed := 0
	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		printerr("Не найдена папка тестов: %s" % UNIT_DIR)
		quit(1)
		return
	var files: Array[String] = []
	for file_name in dir.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			files.append(file_name)
	files.sort()
	for file_name in files:
		var script: GDScript = load("%s/%s" % [UNIT_DIR, file_name])
		if script == null:
			printerr("Не удалось загрузить %s" % file_name)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var case: TestCase = script.new()
			case.begin("%s::%s" % [file_name, method_name])
			await case.call(method_name) # тест может быть корутиной (await process_frame)
			total += 1
			if case.failures.is_empty():
				print("PASS %s::%s" % [file_name, method_name])
			else:
				failed += 1
				for failure in case.failures:
					printerr("FAIL %s" % failure)
	print("Тестов: %d, провалено: %d" % [total, failed])
	quit(1 if failed > 0 else 0)
