# Первоначальное развёртывание UnicNet

Инструкция рассчитана на Linux-хост с Docker Engine и Docker Compose v2. Все прикладные настройки сначала записываются в `Unic.Vault`, и только после этого запускаются Logger, Router, SysLog, Backend и Frontend.

## Состав поставки

| Компонент | Образ |
|---|---|
| PostgreSQL 18 | `cr.yandex/crpi5ll6mqcn793fvu9i/unic/pg:18` |
| Keycloak 26.7.0 | `cr.yandex/crpi5ll6mqcn793fvu9i/unic/keycloak:26.7.0` |
| Vault | `cr.yandex/crpi5ll6mqcn793fvu9i/unic/unicvault:20260825-767ceff843ca` |
| Logger | `cr.yandex/crpi5ll6mqcn793fvu9i/unic/uniclogger:20260825-767ceff843ca` |
| Router | `cr.yandex/crpi5ll6mqcn793fvu9i/unic/unicnetrouter:20260825-767ceff843ca` |
| SysLog | `cr.yandex/crpi5ll6mqcn793fvu9i/unic/unicnetsyslog:20260825-767ceff843ca` |
| Backend | `cr.yandex/crpi5ll6mqcn793fvu9i/unic/unicnetbackend:20260825-767ceff843ca` |
| Frontend | `cr.yandex/crpi5ll6mqcn793fvu9i/unic/unfront:20260825-767ceff843ca` |

Для прикладных образов также опубликован подвижный тег `prod`. Для предсказуемого первого запуска и отката рекомендуется оставлять зафиксированный тег из таблицы.

`Unic.Acl` и `Unic.Storage.Client` являются библиотеками, а не самостоятельными процессами: ACL включён в Backend и Frontend, Storage-клиент — в Backend, SysLog, Logger и Vault. Отдельные образы для них не нужны.

## 1. Подготовка хоста

Нужны Docker Engine 24+, Compose v2, `curl` и `jq`. Скопируйте каталог `deploy/unicnet` на хост и перейдите в него.

Авторизуйтесь в Yandex Container Registry IAM-токеном сервисного аккаунта с правом pull:

```bash
docker login --username iam --password-stdin cr.yandex <<<"$YC_IAM_TOKEN"
docker compose --env-file .env -f compose.yml pull
```

Создайте закрытый bootstrap-файл:

```bash
cp .env.example .env
chmod 600 .env
```

В `.env` перенесите текущие имя БД, пользователя и пароль PostgreSQL, текущие реквизиты администратора Keycloak и публичный URL Keycloak. Создайте отдельный production-ключ `VAULT_JWT_SIGNING_KEY` длиной не менее 32 символов, например `openssl rand -base64 48`. Один и тот же ключ должен использоваться Vault и всеми его клиентами.

Важное исключение из правила хранения ENV в Vault: PostgreSQL должен получить свои bootstrap-реквизиты до запуска Vault, а Vault должен напрямую получить строку подключения и параметры подписи JWT до первого обращения к собственной БД. Клиентам Vault напрямую передаются только `Vault__Url`, `Vault__Jwt__SigningKey`, `Vault__Jwt__Issuer` и `Vault__Jwt__Audience`; все прикладные значения находятся в Vault.

## 2. Подготовка Keycloak

Положите актуальный экспорт realm `unicnet` в `keycloak-import/unicnet-realm.json`. Экспорт должен содержать клиент `FrontUiV2`, роли и группы; пароли пользователей при обычном partial export не переносятся и должны быть назначены отдельно.

Публичный адрес из `KEYCLOAK_PUBLIC_URL` должен быть доступен и браузерам пользователей, и контейнеру Backend. Для текущего стенда это адрес вида `http://<host>:8095`.

## 3. Первый запуск PostgreSQL, Keycloak и Vault

```bash
docker compose --env-file .env -f compose.yml up -d pg keycloak vault
docker compose --env-file .env -f compose.yml ps
curl --fail http://127.0.0.1:8200/openapi/v1.json >/dev/null
```

Не запускайте весь граф до заполнения Vault: сервисы идентифицируются отдельными JWT-владельцами и увидят только свои секреты.

## 4. Загрузка текущих настроек в Vault

```bash
cp vault-values.example.json vault-values.json
chmod 600 vault-values.json
```

Заполните `vault-values.json` текущими значениями из следующих профилей разработки:

| Владелец Vault | Источник текущих значений |
|---|---|
| `Unic.Logger` | `UnicSharedLib/Unic.Logger/Properties/launchSettings.json`, профиль `http_un` |
| `UnicNet.SysLog` | `UnicNet/UnicNet.SysLog/Properties/launchSettings.json` и та же строка PostgreSQL |
| `UnicNet.Router` | `UnicNet/UnicNet.Router/Properties/launchSettings.json` |
| `UnicNet.Backend` | `UnicNet/UnicNet.Backend/Properties/launchSettings.json` |
| `UNFrontV2` | `UnicNet/UnicNet.Front/Properties/launchSettings.json` |

Секретные значения в Git не дублируйте. При переносе строки PostgreSQL сохраните текущие database/user/password, но замените `Host` на Docker DNS-имя `pg`. Локальные URL замените на имена контейнеров из шаблона; URL Keycloak — на `KEYCLOAK_PUBLIC_URL`. Для `Router__Cidr` укажите реальную сеть интерфейса хоста, например значение из `ip -4 route`.

Загрузите или обновите секреты. Скрипт получает отдельный сервисный JWT для каждого владельца, не печатает значения и делает upsert по имени:

```bash
chmod +x bootstrap-vault.sh
./bootstrap-vault.sh vault-values.json
```

После успешной загрузки удалите временный файл с открытыми значениями либо перенесите его в утверждённое защищённое хранилище:

```bash
shred -u vault-values.json
```

## 5. Запуск полного графа

```bash
docker compose --env-file .env -f compose.yml up -d --wait
docker compose --env-file .env -f compose.yml ps
```

Проверки с Docker-хоста:

```bash
curl --fail http://127.0.0.1:8080/
curl --fail http://127.0.0.1:30111/health/ready
curl --fail http://127.0.0.1:30115/health/ready
curl --fail http://127.0.0.1:8001/health/live
curl --fail http://127.0.0.1:8095/realms/unicnet/.well-known/openid-configuration
```

Если сервис не стал healthy, сначала проверьте загрузку его Vault-владельца и только затем логи:

```bash
docker compose --env-file .env -f compose.yml logs --tail=200 vault logger router syslog backend frontend
```

## 6. Обновление и откат

Для обновления измените `UNICNET_IMAGE_TAG` в `.env`, затем выполните:

```bash
docker compose --env-file .env -f compose.yml pull
docker compose --env-file .env -f compose.yml up -d --wait
```

Для отката верните предыдущий неизменяемый тег и повторите те же команды. Данные PostgreSQL сохраняются в named volume `unicnet_postgres-data`; перед обновлением сделайте резервную копию БД.

## 7. Воспроизводимая сборка образов

Все прикладные образы этой поставки собраны без provenance-аттестации. При ручной пересборке обязательно сохраняйте флаг:

```bash
docker build --provenance=false -f UnicNet/UnicNet.Backend/Dockerfile .
```

Для Backend, Frontend, Router и SysLog build context — корень `UniComm.app`; для Logger и Vault — каталог `UnicSharedLib`.
