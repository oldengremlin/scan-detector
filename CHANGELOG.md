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

### Заплановано (див. README → TODO)
- Збереження live-стану `scan`/`level*`/`srv_*` між перезапусками `nft-scan-detector`.
- Автоматичне підхоплення нових docker-мереж без ручного рестарту сервісу.
- Опціональне від'єднання від Docker (генерація лише `input`, без `forward`).
