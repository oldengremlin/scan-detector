# Changelog

Формат базується на [Keep a Changelog](https://keepachangelog.com/uk/1.1.0/).
Ведеться українською.

## [Unreleased]

### Додано
- Повний `README.md`: опис проєкту, вимоги, встановлення, mermaid-діаграма
  пакетного flow nft-правил, опис override-файлів `trusted`/`ignore`/`permanentBlock`,
  розділ "Відомі обмеження і TODO".
- `CLAUDE.md` — правила роботи над проєктом (мова спілкування, обов'язкове
  оновлення CHANGELOG/README при змінах коду, стиль коду).
- `systemd/scan-detector.service` — юніт для запуску `nft-scan-detector` після
  старту Docker (опційна залежність через `After=`, без `Requires=`), як заміна
  виклику з `/etc/rc.local`.
- Розділ "Історія" в README — походження ідеї (MikroTik RouterOS), попередня
  вужча реалізація на `iptables`+`ipset` (лише SSH-брутфорс), час появи
  поточної nftables-версії.
- `src/bash/` — `nft-scan-detector` і `scan-detect-tool` перенесені сюди з
  кореня репозиторію.
- Збереження/відновлення live-стану `scan`/`level0..level15`/`srv_*`
  (і IPv6-відповідників) між перезапусками `nft-scan-detector`: перед
  `delete table` знімається знімок елементів усіх dynamic-сетів разом із
  рештою таймауту (`nft -j` + `jq`), і одразу після перестворення сетів він
  відновлюється в тій самій транзакції (`add element ... timeout Ns`).
  Знімок додатково лягає в `/var/lib/nft-scandetect/live-state-<ts>.tsv`.
- Прапорець `--reset-live-state` у `nft-scan-detector` — повертає стару
  поведінку (чисті сети після перестворення), якщо live-стан зберігати не
  треба.
- Прапорець `--no-docker` у `nft-scan-detector` — не генерує ланцюг `forward`
  і per-bridge правила, лишається тільки `input`. Вмикається і вручну, і
  автоматично, якщо на хості немає бінарника `docker`. Незалежний від
  `--reset-live-state` — прапорці вільно комбінуються.
- Прапорці `--stop`/`--stop-docker` у `nft-scan-detector` — окремий режим,
  який атомарно знімає ланцюг `forward` із живої таблиці (`input`, сети й
  live-стан не чіпає), не перегенеровуючи нічого. `--stop-docker` додатково
  зупиняє `docker.socket`, потім `docker.service`. Взаємовиключні з
  `--reset-live-state`/`--no-docker`. Повернення `forward` — звичайний
  запуск без `--stop*`.
- `src/bash/docker-network-watch` + `systemd/docker-network-watch.service` —
  опційний слухач `docker events` (create/destroy мереж), що рестартує
  `scan-detector.service` при появі/зникненні docker-бриджа, з дебаунсом
  (2s тиші) на серію подій від одної дії (напр. `docker compose up`).
  `Requires=docker.service` у юніті — зупиняється разом з Docker, зокрема
  через `--stop-docker`.
- Конфігурований пріоритет hook'ів `input`/`forward` (дефолт `-50`, як і
  було). Файл `/etc/nft-scandetect/priority` — рівно одне ціле число, без
  коментарів (читається через `head -1`, не парситься як інші override-файли).
  Нелегітимне значення чи зіпсований файл фолбечать на дефолт із
  попередженням у stderr, ruleset не ламається. `nft-scan-detector` створює
  файл із дефолтом при першому запуску.
- `scan-detect-tool --set-priority N` — перевизначає пріоритет: пише файл і
  рестартує `scan-detector.service` (на відміну від `--add-*`, це не "живий"
  `add element` — зміна hook'а вимагає повної перегенерації).
- Конфігурована кількість рівнів ескалації і їхні таймаути:
  `/etc/nft-scandetect/level_timeouts` — рядки `N:timeout`, суцільно від 0 без
  пропусків/дублів (кількість рядків = кількість рівнів `level0..levelN` /
  `level6_0..level6_N`, за замовчуванням 16 як і було). Невалідний формат —
  фолбек на вбудований дефолт з попередженням. `gen_level_sets`/`gen_level_rules`
  змін не потребували — просто читають перевизначений `LEVEL_TIMEOUTS`/`LAST_LEVEL`.
- Конфігуровані захищені порти каскаду `srv_*`/`srv6_*`:
  `/etc/nft-scandetect/srv_ports` — рядки `proto/port` (`tcp` чи `udp`, за
  замовчуванням `tcp/80`+`tcp/443` як і було). Порти групуються по протоколу,
  кожен протокол — окремий `dport`-матч, усі пишуть у ті самі спільні сети
  `srv_normal`/`check0`/`check1`/`block` (throttle по saddr, не per-протокол).
  Невалідний рядок пропускається з попередженням, решта застосовується.
- Конфігуровані таймаути 4 стадій `srv_*`: `/etc/nft-scandetect/srv_timeouts`
  — рядки `stage:timeout`, рівно `normal`/`check0`/`check1`/`block` (за
  замовчуванням `5s`/`10s`/`15s`/`1m` як і було). Неповний набір — фолбек на
  дефолт цілком.
- Прапорець `--init` у `nft-scan-detector` — окремий режим: лише досіює
  відсутні override-файли вбудованими дефолтами (`seed_all_config_if_missing`,
  спільна для `--init` і звичайної генерації), не чіпає живу таблицю, Docker
  чи live-стан. Взаємовиключний з рештою прапорців. `scan-detect-tool --init`
  — тонка обгортка, делегує `sudo nft-scan-detector --init` (щоб не
  дублювати логіку сідінгу в другому скрипті).
- `scan-detector.service` тепер впорядкований і `After=nftables.service` (не
  лише `docker.service`) — на старті системи наша таблиця застосовується
  вже після того, як накотився `/etc/nftables.conf`, а не в гонці з ним.
- Опційний drop-in `systemd/nftables.service.d/restart-scan-detector.conf`
  (`ExecStartPost=-...systemctl restart scan-detector.service`) — якщо на
  хості є вендорський `nftables.service` (типово Debian/Ubuntu, керує
  `/etc/nftables.conf`), кожен його старт/рестарт виконує `flush ruleset` і
  стирає **всю** живу таблицю, включно з `inet scanDetector` (перевірено
  наживо в продакшн-інсталяції — саме так і сталось). Drop-in автоматично
  повертає нашу таблицю одразу після, живий стан каскаду це переживає.

### Виправлено
- **Перший запуск на чистому хості завжди падав.** `nft -c -f` (dry-run
  перевірка синтаксису) не дозволяє `delete table`, якщо таблиці ще нема —
  а на щойно встановленому хості її й нема. Тепер перед `delete table`
  скрипт спершу робить ідемпотентний `add table` (без помилки, існує вона
  чи ні), тож і чисте встановлення, і повторні запуски проходять однаково.
- **`permanentBlock`/`permanentBlock6` з порожнім override-файлом валили
  скрипт під `set -e`.** Коли override-файл існує, але не містить жодного
  реального значення (лише коментарі/порожній — типовий стан для
  permanentBlock одразу після bootstrap), `grep` без збігів виходив з кодом
  1, і через `pipefail` це мовчки завершувало весь скрипт. Тепер порожній
  результат grep не вважається помилкою.
- **README радив `enable --now` для оновлення скрипта на вже встановленому
  хості.** На вже активному (`active (exited)`) юніті `start`/`enable --now`
  — no-op, ExecStart повторно не виконується; `daemon-reload` теж не
  рестартовує процес. Тобто оновлені файли на диску ніколи не підхоплювались.
  Новий розділ README "Оновлення" явно вимагає `systemctl restart` для
  апгрейду (`enable --now` лишається лише для першого встановлення).

