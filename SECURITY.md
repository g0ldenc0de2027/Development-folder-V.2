# Security policy

## Поддерживаемая версия
Проверяется текущая версия из ветки main. Другие версии не обещают исправления.

## Сообщение об уязвимости
Не публикуйте секреты и детали неустраненной уязвимости в публичном issue. Используйте механизм Private vulnerability reporting GitHub, если он доступен, или свяжитесь с владельцем репозитория через профиль GitHub. Не присылайте пароли, токены, cookies или MFA-коды.

## Базовые меры
- GitHub Actions получают только read-доступ к репозиторию.
- Actions в workflow закрепляются полным commit SHA.
- На каждом PR выполняются проверки качества, YAML workflow и утечки секретов; проверки не используют path filters.
- Dependabot и уведомления об уязвимостях включены на уровне репозитория.
- GitHub provider-pattern secret scanning и push protection включены. Generic patterns и validity checks недоступны в текущем personal Free профиле и не засчитываются как покрытие; Gitleaks дополняет, но не заменяет GitHub scanning.
