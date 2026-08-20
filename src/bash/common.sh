#!/bin/bash
# shellcheck shell=bash

# common.sh — спільний код nft-scan-detector і scan-detect-tool.
#
# Обидва скрипти мусять однаково бачити: назви таблиць, перелік додаткових
# srv-таблиць (підкаталоги OVERRIDE_DIR) і правила валідації елементів
# списків. Доки це були три окремі копії в двох файлах, будь-яка
# розсинхронізація означала б тихий баг: scan-detect-tool промине таблицю,
# про яку не знає, і живі сети розійдуться з конфігом.
#
# Цей файл нічого не виконує -- лише визначає константи й функції. Він
# НЕ призначений для прямого запуску, лише для `source`.

# --- спільні константи ---

TABLE_FAMILY="inet"
OVERRIDE_DIR="/etc/nft-scandetect"
DEFAULT_TABLE_NAME="scanDetector"
DEFAULT_TABLE_NAME_SRV="srvProtector"

# --- назви таблиць з override-файлів ---

# Легітимна назва nft-таблиці: літери/цифри/підкреслення, не з цифри.
# Той самий критерій застосовується і до назв підкаталогів (= назв
# додаткових srv-таблиць) у discover_extra_srv_dirs нижче.
_valid_nft_identifier() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# _read_table_name_file FILE DEFAULT -- спільна реалізація для обох
# table_name-файлів: РІВНО один рядок, легітимний nft-ідентифікатор.
# Відсутній файл чи нелегітимний вміст -- фолбек на DEFAULT (з
# попередженням у stderr у другому випадку).
_read_table_name_file() {
    local file="$1" fallback="$2" raw
    if [[ -f "$file" ]]; then
        raw=$(head -1 "$file" | tr -d '[:space:]')
        if _valid_nft_identifier "$raw"; then
            echo "$raw"
            return 0
        fi
        echo "УВАГА: $file містить нелегітимну назву таблиці ('$raw') -- використовую дефолт ${fallback}." >&2
    fi
    echo "$fallback"
}

read_table_name() {
    _read_table_name_file "${OVERRIDE_DIR}/table_name" "$DEFAULT_TABLE_NAME"
}

read_table_name_srv() {
    _read_table_name_file "${OVERRIDE_DIR}/table_name_srv" "$DEFAULT_TABLE_NAME_SRV"
}

# --- додаткові srv-таблиці (підкаталоги OVERRIDE_DIR) ---

# discover_extra_srv_dirs -- кожен підкаталог ${OVERRIDE_DIR} це ДОДАТКОВА
# srv-протектор-подібна таблиця (своя table inet <назва каталогу>, свої
# srv_ports/srv_timeouts/priority; решта успадковується з головного
# конфігу). Друкує валідні назви по рядку, відсортовано.
#
# Каталог пропускається (з попередженням) якщо назва не легітимний
# nft-ідентифікатор або збігається з уже наявною таблицею. Порівняння
# робиться з ${TABLE_NAME}/${TABLE_NAME_SRV} -- обидва скрипти зобов'язані
# визначити ці змінні ДО виклику (обидва це роблять одразу після source).
#
# Результат КЕШУЄТЬСЯ: функція викликається по кілька разів за прогін, і без
# кешу те саме попередження про кожен пропущений каталог друкувалось би в
# stderr стільки ж разів поспіль. Кеш заповнюється ПРЯМИМ викликом (див.
# warm_extra_srv_dirs_cache) -- підстановки $(...) і <(...) форкають
# підшелл, і встановлений усередині них кеш загубився б.
EXTRA_SRV_DIRS_CACHED=0
EXTRA_SRV_DIRS_CACHE=""
discover_extra_srv_dirs() {
    if [[ $EXTRA_SRV_DIRS_CACHED -eq 0 ]]; then
        local d name result=""
        if [[ -d "$OVERRIDE_DIR" ]]; then
            for d in "${OVERRIDE_DIR}"/*/; do
                [[ -d "$d" ]] || continue
                name="$(basename "$d")"
                if ! _valid_nft_identifier "$name"; then
                    echo "УВАГА: каталог ${d} -- не легітимний nft-ідентифікатор, пропускаю як додаткову srv-таблицю." >&2
                    continue
                fi
                if [[ "$name" == "${TABLE_NAME:-}" || "$name" == "${TABLE_NAME_SRV:-}" ]]; then
                    echo "УВАГА: каталог ${d} збігається з назвою вже наявної таблиці (${TABLE_NAME:-}/${TABLE_NAME_SRV:-}), пропускаю." >&2
                    continue
                fi
                result+="${name}"$'\n'
            done
        fi
        EXTRA_SRV_DIRS_CACHE=$(printf '%s' "$result" | sort -u)
        EXTRA_SRV_DIRS_CACHED=1
    fi
    [[ -n "$EXTRA_SRV_DIRS_CACHE" ]] && printf '%s\n' "$EXTRA_SRV_DIRS_CACHE"
    return 0
}

# Заповнює кеш discover_extra_srv_dirs ОДНИМ прямим викликом (без $(...)/
# <(...), які форкають підшелл). Викликається один раз на самому початку
# роботи обох скриптів -- усі подальші виклики вже через підстановки
# успадковують заповнений кеш від форка й каталог не пересканують.
warm_extra_srv_dirs_cache() {
    discover_extra_srv_dirs >/dev/null
}

# --- валідація елементів списків trusted/ignore/permanentBlock ---

is_ipv6() {
    [[ "$1" == *:* ]]
}

# validate_ip_element VALUE -- чи схоже VALUE на елемент, який можна
# безпечно підставити в `add element ... { VALUE }`. Приймає одиничну
# адресу, CIDR-префікс і interval-діапазон "a-b" (сети trusted/ignore/
# permanentBlock оголошені з `flags interval`, тож діапазони легітимні).
#
# Це не сувора перевірка "чи існує така адреса" (октет 999 пройде -- його
# відхилить уже сам nft), а перевірка КЛАСУ СИМВОЛІВ: рядок не має містити
# нічого, чим можна було б закрити дужку й дописати власні nft-команди.
# Саме це і є метою -- не дати ручному редагуванню override-файлу
# перетворитись на непомітну ін'єкцію в ruleset.
validate_ip_element() {
    local v="$1"
    [[ -z "$v" ]] && return 1
    local v4='([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?'
    local v6='[0-9a-fA-F:]+(/[0-9]{1,3})?'
    if is_ipv6 "$v"; then
        [[ "$v" =~ ^${v6}(-${v6})?$ ]]
    else
        [[ "$v" =~ ^${v4}(-${v4})?$ ]]
    fi
}

# --- завантаження common.sh з обох скриптів ---
#
# Патерн для викликача (обидва скрипти роблять саме так):
#
#   for _c in "/usr/local/lib/nft-scandetect/common.sh" \
#             "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"; do
#       [[ -r "$_c" ]] && { . "$_c"; break; }
#   done
#
# Перший шлях -- штатне місце після встановлення, другий -- сусідній файл
# у репозиторії (щоб скрипти працювали прямо з src/bash без установки).
