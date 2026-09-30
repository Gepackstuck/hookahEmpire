#!/usr/bin/env bash
# Прогон проверок проекта: импорт, parse-check скриптов, юнит-тесты, headless-запуск.
# Весь вывод дублируется в tests/last_run.log (файл в .gitignore).
#
# Использование (из любой папки):
#   export GODOT_BIN="/путь/к/Godot.app/Contents/MacOS/Godot"
#   tools/run_checks.sh
set -u

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$PROJECT_DIR/tests/last_run.log"
cd "$PROJECT_DIR" || exit 2

if [[ -z "${GODOT_BIN:-}" || ! -x "$GODOT_BIN" ]]; then
	echo "GODOT_BIN не задан или не исполняемый: '${GODOT_BIN:-}'" >&2
	echo "Укажите путь к бинарнику внутри Godot.app (.../Godot.app/Contents/MacOS/Godot)." >&2
	exit 2
fi

: > "$LOG_FILE"
FAILED=0

log() { echo "$*" | tee -a "$LOG_FILE"; }

# run_step <название> <команда...>: выполняет команду, пишет вывод в лог и консоль.
run_step() {
	local name="$1"; shift
	log ""
	log "=== $name ==="
	log "\$ $*"
	local out rc
	out="$("$@" 2>&1)"; rc=$?
	echo "$out" | tee -a "$LOG_FILE"
	# Godot может вернуть 0 при ошибках скриптов — ловим их по тексту.
	if [[ $rc -ne 0 ]] || grep -qE "SCRIPT ERROR|Parse Error|ERROR:" <<<"$out"; then
		log "--> FAIL: $name (код $rc)"
		FAILED=1
	else
		log "--> OK: $name"
	fi
}

log "Godot: $("$GODOT_BIN" --version 2>&1)"
log "Дата: $(date '+%Y-%m-%d %H:%M:%S')"

run_step "Импорт ресурсов" "$GODOT_BIN" --headless --path . --import

while IFS= read -r script; do
	run_step "Parse-check: ${script#./}" "$GODOT_BIN" --headless --path . --check-only --script "res://${script#./}"
done < <(find scripts tests -name '*.gd' | sort)

run_step "Юнит-тесты" "$GODOT_BIN" --headless --path . --script res://tests/run_tests.gd
run_step "Headless-запуск main scene" "$GODOT_BIN" --headless --path . --quit-after 5

log ""
if [[ $FAILED -eq 0 ]]; then
	log "ИТОГО: ВСЕ ПРОВЕРКИ ПРОШЛИ"
else
	log "ИТОГО: ЕСТЬ ОШИБКИ (см. выше)"
fi
exit $FAILED
