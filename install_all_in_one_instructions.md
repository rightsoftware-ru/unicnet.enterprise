<!-- TOC start (generated with https://github.com/derlin/bitdowntoc) -->

- [Инструкция по установке и настройке Unicnet ](#-unicnet)
- [Архитектура установки](#-)
   * [Установка на 1-м сервере](#-1-)
- [Переменные окружения](#--env)
- [Автоматизированная установка с помощью скрипта](#--1)
   * [Шаги по использованию скрипта:](#--2)
- [Ручная установка](#--3)
   * [Порядок установки](#--4)
   * [Установка docker и docker-compose](#-docker-docker-compose)
   * [Подключение к репозиторию Unicnet](#-unicnet-1)
   * [Установка необходимых компонентов одним compose файлом](#-compose-)
      + [Создание docker сети для compose файла](#-docker-compose-)
   * [Удаление старого volume для unicnet.mongo](#-volume-unicnetmongo)
      + [Шаги по удалению Volume:](#-volume)
      + [Настройка переменных окружения](#--5)
      + [Запуск compose файла](#-compose--1)
   * [Настройка Keycloak](#-keycloak)
      + [Создание realm](#-realm)
   * [Настройка unicnet](#-unicnet-2)
      + [Перезапуск сервисов](#--6)
      + [Вход в unicnet](#-unicnet-3)
- [Деинсталляция (удаление)](#uninstall)
- [F.A.Q](#faq)

<!-- TOC end -->



<!-- TOC --><a name="-unicnet"></a>
## Инструкция по установке и настройке Unicnet 

<!-- TOC --><a name="-"></a>
## Архитектура установки

<!-- TOC --><a name="-1-"></a>
### Установка на 1-м сервере

![](./unicnet_assets/unicnet_arch.png "Архитектура установки на 1-м сервере")

<!-- TOC --><a name="--env"></a>
## Переменные окружения

Перед началом установки необходимо подготовить переменные окружения. Все переменные задаются через `export` в текущей сессии или через файл `export_variables.txt`.

### Быстрая настройка переменных

Используйте готовый файл `export_variables.txt`:

```bash
cd unicnet.enterprise
source export_variables.txt
```

Или экспортируйте переменные вручную (см. список ниже).

### Основные переменные, которые необходимо настроить:

#### 1. IP адрес сервера

**Обязательно** замените все вхождения `127.0.0.1` или `internal_IP` на внешний IP адрес вашего сервера:
- В файле `app/unicnet-realm.json` - замените `internal_IP` на ваш IP (например, `192.168.1.100`)

#### 2. PostgreSQL (используется Keycloak)

- `POSTGRES_DB` - база данных PostgreSQL (по умолчанию: `unicnetdb`)
- `POSTGRES_USER` - пользователь PostgreSQL (по умолчанию: `unicnet`)
- `POSTGRES_PASSWORD` - пароль PostgreSQL (по умолчанию: `postgres123`)

#### 3. MongoDB - root пользователь (для инициализации)

- `MONGO_INITDB_ROOT_USERNAME` - root пользователь MongoDB (по умолчанию: `unicnet`)
- `MONGO_INITDB_ROOT_PASSWORD` - пароль root пользователя (по умолчанию: `mongo123`)
- `MONGO_INITDB_DATABASE` - основная база данных (по умолчанию: `unicnet_db`)

#### 4. MongoDB - пользователи для сервисов

- `MONGO_UNICNET_DB` - база данных для UnicNet (по умолчанию: `unicnet_db`)
- `MONGO_UNICNET_USER` - пользователь MongoDB для UnicNet (по умолчанию: `unicnet`)
- `MONGO_UNICNET_PASSWORD` - пароль пользователя MongoDB (по умолчанию: `unicnet_pass_123`)
- `MONGO_LOGGER_DB` - база данных для Logger (по умолчанию: `logger_db`)
- `MONGO_LOGGER_USER` - пользователь MongoDB для Logger (по умолчанию: `logger_user`)
- `MONGO_LOGGER_PASSWORD` - пароль пользователя Logger (по умолчанию: `logger_pass_123`)
- `MONGO_VAULT_DB` - база данных для Vault (по умолчанию: `vault_db`)
- `MONGO_VAULT_USER` - пользователь MongoDB для Vault (по умолчанию: `vault_user`)
- `MONGO_VAULT_PASSWORD` - пароль пользователя Vault (по умолчанию: `vault_pass_123`)

#### 5. Keycloak

- `KEYCLOAK_ADMIN_USER` - имя администратора Keycloak (по умолчанию: `unicnet`)
- `KEYCLOAK_ADMIN_PASSWORD` - пароль администратора Keycloak (по умолчанию: `admin123`)

#### 6. Лицензия (используется всеми сервисами)

- `UniCommLicenseData` - данные лицензии (по умолчанию: `default_license_data`)

> **Важно**: 
> - Если вы измените пароли MongoDB, убедитесь, что они совпадают при создании пользователей в MongoDB (шаг 5 скрипта `install.sh`)
> - При использовании автоматической установки через скрипт `install.sh`, большинство переменных настраиваются автоматически
> - При ручной установке все переменные необходимо экспортировать через `export` перед запуском `docker-compose up`
> - Переменные окружения можно задать через файл `export_variables.txt` командой `source export_variables.txt`

<!-- TOC --><a name="--1"></a>
## Автоматизированная установка с помощью скрипта

Скрипт `install.sh` — это интерактивный помощник, который автоматизирует весь процесс установки UnicNet Enterprise. Он выполняет все необходимые шаги: от проверки зависимостей до создания пользователей в Keycloak.

**Как работает скрипт:**
1. Сначала он собирает у вас необходимые данные (IP адрес, имя пользователя, пароли и т.д.) и сохраняет их в конфигурационный файл `unicnet_installer.conf`
2. Затем выполняет 11 последовательных шагов установки автоматически
3. На каждом шаге показывает, что именно делает, и выводит информацию о прогрессе
4. В конце выводит все URL и учетные данные для доступа к системе

**Что делает скрипт на каждом шаге:**

**Шаг 1: Проверка зависимостей** — Проверяет наличие Docker и docker-compose. Использует jq через Docker контейнер для работы с JSON. Если Docker не установлен — выводит ошибку и завершает работу.

**Шаг 2: Создание Docker сети** — Создает сеть `unicnet_network` для связи между контейнерами. Если сеть уже существует — пропускает этот шаг.

**Шаг 3: Docker login в Yandex CR** — Логинится в Yandex Container Registry для доступа к образам (опционально, можно пропустить, если токен не задан).

**Шаг 4: Запуск Docker Compose** — Запускает все сервисы: PostgreSQL, MongoDB, Keycloak, Backend, Frontend, Logger, Syslog, Vault, Router. Автоматически экспортирует переменные окружения MongoDB перед запуском.

**Шаг 5: Создание пользователей и БД в MongoDB** — Читает переменные окружения из работающих контейнеров, парсит строки подключения MongoCS и создает/обновляет пользователей и базы данных в MongoDB для сервисов: UnicNet, Logger, Vault.

**Шаг 6: Получение токена Vault** — Подключается к контейнеру Vault, устанавливает curl (если нужно) и получает токен доступа к Vault через API.

**Шаг 7: Создание секрета в Vault** — Создает секрет `UNFrontV2` в Vault с метаданными: URL для Keycloak, Backend, Logger, Syslog (используя внешние IP адреса), а также credentials администратора Keycloak.

**Шаг 8: Определение схемы/порта Keycloak** — Автоматически определяет, на каком порту работает Keycloak (8095) и использует ли он HTTP или HTTPS. Проверяет доступность через docker-compose port и переменные окружения.

**Шаг 9: Ожидание готовности Keycloak** — Ждет, пока Keycloak полностью запустится и станет доступен, проверяя endpoint `/realms/master`.

**Шаг 10: Импорт realm** — Импортирует конфигурацию realm из файла `app/unicnet-realm.json` в Keycloak через API. Автоматически заменяет `internal_IP` на ваш IP адрес. Если realm не был указан пользователем, автоматически берет его из JSON файла. Получает токен администратора Keycloak для последующих операций.

**Шаг 11: Создание пользователя и назначение 3 групп** — Создает пользователя для входа в UnicNet, устанавливает ему пароль и добавляет в 3 группы (ищет группы с паттерном `unicnet_*_group` или использует первые доступные группы).

> **Примечание**: Скрипт автоматически выполняет все эти шаги при выборе опции "0" в меню. Вы также можете выполнять шаги по отдельности, выбирая соответствующие опции в меню (1-11).

<!-- TOC --><a name="--2"></a>
### Шаги по использованию скрипта:

1. **Клонируйте репозиторий** (если еще не клонирован):

   ```bash
   git clone https://github.com/rightsoftware-ru/unicnet.enterprise.git
   cd unicnet.enterprise
   ```

2. **Подготовьте переменные окружения** (опционально):

   Если вы хотите использовать нестандартные значения, экспортируйте переменные перед запуском скрипта:
   
   ```bash
   source export_variables.txt
   ```
   
   Или экспортируйте вручную нужные переменные (см. раздел "Переменные окружения" выше).

3. **Сделайте скрипт исполняемым**:

   ```bash
   chmod +x install.sh
   ```

4. **Запустите скрипт**:

   ```bash
   ./install.sh
   ```

5. **Введите данные при запросе**:
   
   При первом запуске скрипт попросит вас ввести:
   - **IP адрес сервера** — внешний IP, на котором будут доступны сервисы (например, `192.168.1.100`)
   - **Realm name** — имя realm для Keycloak (можно оставить пустым — скрипт автоматически определит из `app/unicnet-realm.json`)
   - **Имя нового пользователя** — логин для входа в UnicNet (по умолчанию: `unicadmin`)
   - **Пароль нового пользователя** — можно оставить пустым, скрипт сгенерирует безопасный пароль автоматически
   - **Email нового пользователя** — email адрес (по умолчанию: `unicadmin@local`)
   - **Yandex CR токен** — OAuth токен для доступа к реестру (есть значение по умолчанию, можно оставить)

   > **Важно**: 
   > - Credentials администратора Keycloak автоматически читаются из контейнера, их не нужно вводить
   > - При первом запуске скрипт сохранит все введенные данные в файл `unicnet_installer.conf` (права 600). При следующих запусках он автоматически загрузит эти данные, и вам не нужно будет вводить их снова.

6. **Выберите действие в меню**:

   После ввода данных скрипт покажет меню:
   - **Опция "0"** — Выполнить всё по порядку (рекомендуется для первой установки)
   - **Опция "1"** — Установить зависимости (проверка Docker, docker-compose)
   - **Опция "2"** — Создать сеть Docker
   - **Опция "3"** — Docker login в Yandex CR (опционально)
   - **Опция "4"** — Запустить Docker Compose
   - **Опция "5"** — Создать пользователей и БД в MongoDB
   - **Опция "6"** — Получить токен Vault
   - **Опция "7"** — Создать секрет в Vault
   - **Опция "8"** — Определить порт/схему Keycloak
   - **Опция "9"** — Дождаться готовности Keycloak
   - **Опция "10"** — Импортировать realm
   - **Опция "11"** — Создать пользователя и назначение 3 групп
   - **Опция "12"** — Показать итоги/URL (показывает все адреса и учетные данные)
   - **Опция "13"** — Полная деинсталляция (удаляет контейнеры, volumes, сеть, образы)
   - **Опция "14"** — Полная переустановка (сначала удаляет всё, потом устанавливает заново)
   - **Опция "q"** — Выход

7. **Дождитесь завершения**:

   Скрипт выполнит все шаги и покажет итоговую информацию:
   - Приложение: `http://<SERVER_IP>:8080`
   - Keycloak Admin: `<admin_user> / ***` (пароль скрыт, берется из контейнера) на `<KC_URL>`
   - Realm: `<realm_name>`
   - Пользователь для входа: `<new_user> / <new_user_pass>`
   - Groups: список назначенных групп
   - Backend Swagger: `http://<SERVER_IP>:30111/swagger/index.html`
   - RabbitMQ: `http://<SERVER_IP>:15672/` (логин/пароль как BASE_USER/BASE_PASS)

**Что делать, если что-то пошло не так:**

- Если скрипт остановился с ошибкой — посмотрите, на каком шаге это произошло. Детали ошибки выводятся на экран.
- Проверьте логи контейнеров: `docker logs <container_name>` или используйте папку `log/` (если собирали логи)
- Вы можете выполнить отдельные шаги через меню (опции 1-11), чтобы повторить проблемный шаг
- Если нужно начать заново — используйте опцию 13 (деинсталляция), затем опцию 0 (полная установка)
- Проверьте, что все переменные окружения экспортированы: `env | grep -E 'MONGO_|POSTGRES_|KEYCLOAK_'`

<!-- TOC --><a name="--3"></a>
## Ручная установка

<!-- TOC --><a name="--4"></a>
### Порядок установки

1. Клонирование репозитория
2. Установка зависимостей (Docker, docker-compose)
3. Экспорт переменных окружения
4. Создание Docker сети
5. Авторизация в Yandex Container Registry (опционально)
6. Запуск всех сервисов через Docker Compose
7. Создание пользователей и баз данных в MongoDB
8. Получение токена Vault
9. Создание секрета в Vault
10. Определение порта/схемы Keycloak
11. Ожидание готовности Keycloak
12. Импорт realm в Keycloak
13. Создание пользователя и назначение групп в Keycloak

<!-- TOC --><a name="-docker-docker-compose"></a>
### Установка docker и docker-compose

Установка производится за рамками инструкции. Рекомендуется установить docker с официального сайта https://docs.docker.com/engine/install/

<!-- TOC --><a name="-unicnet-1"></a>
### Клонирование репозитория

Клонируйте репозиторий UnicNet Enterprise:

```bash
git clone https://github.com/rightsoftware-ru/unicnet.enterprise.git
cd unicnet.enterprise
```

В директории `./app` должны находиться следующие файлы:
- `docker-compose.yml` - Docker Compose файл со всеми сервисами
- `unicnet-realm.json` - конфигурация realm для Keycloak

> **Важно**: Перед продолжением убедитесь, что все необходимые переменные окружения экспортированы (см. раздел "Переменные окружения" выше). Используйте `source export_variables.txt` для быстрой настройки.

<!-- TOC --><a name="-docker-compose-"></a>
#### Создание docker сети для compose файла

Создайте сеть командой:

```bash
docker network create unicnet_network
```

<!-- TOC --><a name="-volume-unicnetmongo"></a>
### Удаление старого volume для unicnet.mongo

Если вы ранее устанавливали unicnet на данном сервере с другими настройками для контейнера unicnet.mongo, настоятельно рекомендуется удалить старый volume. Пожалуйста, учтите, что это приведет к потере всех данных, хранящихся в unicnet.mongo.

<!-- TOC --><a name="-volume"></a>
#### Шаги по удалению Volume:

1. Показать список существующих Volume: Для отображения всех доступных volume выполните следующую команду:

   ```bash
   docker volume ls
   ```

2. Удалить старый Volume: После того как вы определитесь с необходимым volume, используйте следующую команду для его удаления:

   ```bash
   docker volume rm имя_вашего_volume
   ```

Убедитесь, что вы хотите удалить именно тот volume, который связан с unicnet.mongo, поскольку процесс удаления является необратимым и приведет к утрате всех данных.

<!-- TOC --><a name="--5"></a>
#### Настройка переменных окружения

Экспортируйте переменные окружения перед запуском Docker Compose:

```bash
# Быстрый способ - использовать готовый файл
source export_variables.txt

# Или экспортировать вручную
export POSTGRES_DB=unicnetdb
export POSTGRES_USER=unicnet
export POSTGRES_PASSWORD=postgres123
# ... и так далее (см. раздел "Переменные окружения" выше)
```

> **Важно**: 
> - Все переменные должны быть экспортированы в текущей сессии shell перед запуском `docker-compose up`
> - Если вы измените значения по умолчанию, убедитесь, что они согласованы между всеми сервисами
> - IP адреса заменяются в файле `app/unicnet-realm.json` (замените `internal_IP` на ваш внешний IP)

<!-- TOC --><a name="-compose--1"></a>
#### Авторизация в Yandex Container Registry (опционально)

Если у вас есть OAuth токен для Yandex Container Registry, выполните:

```bash
echo "<YOUR_YCR_TOKEN>" | docker login --username oauth --password-stdin cr.yandex
```

Если токен не задан, этот шаг можно пропустить (образы могут быть доступны без авторизации).

#### Запуск Docker Compose

1. **Перейдите в директорию app**:

```bash
cd app
```

2. **Убедитесь, что переменные окружения экспортированы** (если еще не сделали):

```bash
cd ..
source export_variables.txt
cd app
```

3. **Запустите контейнеры**:

```bash
docker compose -f docker-compose.yml up -d
```

Или с ожиданием готовности сервисов (если поддерживается):

```bash
docker compose -f docker-compose.yml up -d --wait
```

4. **Проверьте статус контейнеров**:

```bash
docker compose -f docker-compose.yml ps
```

Должны быть запущены следующие контейнеры:
- `unicnet.postgres` - PostgreSQL база данных (порт 5432)
- `unicnet.mongo` - MongoDB база данных (порт 27017)
- `unicnet.keycloak` - Keycloak (порты 8095, 8096, 9990)
- `unicnet.backend` - Backend сервис (порт 30111)
- `unicnet.frontend` - Frontend приложение (порты 8080, 8081)
- `unicnet.logger` - Сервис логирования (порт 8082)
- `unicnet.syslog` - Syslog сервис (порт 8001)
- `unicnet.vault` - Vault сервис (порт 8200)
- `unicnet.router` - Router сервис (порт 30115)

4. **Проверьте логи контейнеров** (при необходимости):

```bash
docker logs unicnet.mongo
docker logs unicnet.keycloak
docker logs unicnet.backend
```

### Создание пользователей и баз данных в MongoDB

После запуска контейнера MongoDB создайте необходимые базы данных и пользователей. Скрипт `install.sh` делает это автоматически на шаге 5, но при ручной установке выполните следующие команды:

**Важно**: Используйте те же значения переменных окружения, которые были экспортированы ранее (MONGO_UNICNET_*, MONGO_LOGGER_*, MONGO_VAULT_*).

1. **Подключитесь к MongoDB**:

```bash
docker exec -it unicnet.mongo mongosh -u ${MONGO_INITDB_ROOT_USERNAME:-unicnet} -p ${MONGO_INITDB_ROOT_PASSWORD:-mongo123} --authenticationDatabase admin
```

2. **Создайте базы данных и пользователей**:

```javascript
// Создайте базу данных для UnicNet
use ${MONGO_UNICNET_DB:-unicnet_db}
db.createUser({
  user: "${MONGO_UNICNET_USER:-unicnet}",
  pwd: "${MONGO_UNICNET_PASSWORD:-unicnet_pass_123}",
  roles: [{ role: "readWrite", db: "${MONGO_UNICNET_DB:-unicnet_db}" }]
})

// Создайте базу данных для Logger
use logger_db
db.createUser({
  user: "logger_user",
  pwd: "logger_pass_123",
  roles: [{ role: "readWrite", db: "logger_db" }]
})

// Создайте базу данных для Vault
use vault_db
db.createUser({
  user: "vault_user",
  pwd: "vault_pass_123",
  roles: [{ role: "readWrite", db: "vault_db" }]
})
```

> **Примечание**: Пароли должны соответствовать экспортированным переменным окружения (MONGO_*_PASSWORD) или значениям по умолчанию из docker-compose.yml

<!-- TOC --><a name="-keycloak"></a>
### Настройка Keycloak

#### Подготовка realm файла

Откройте файл `app/unicnet-realm.json` и замените все вхождения `internal_IP` на внешний IP адрес вашего сервера.

> Например, если ваш IP адрес `192.168.1.100`, выполните:
> ```bash
> sed -i 's/internal_IP/192.168.1.100/g' app/unicnet-realm.json
> ```

#### Ожидание готовности Keycloak

Дождитесь, пока Keycloak полностью запустится (обычно 30-60 секунд):

```bash
# Проверьте логи
docker logs unicnet.keycloak

# Или проверьте доступность через curl
curl -f http://localhost:8095/health/ready || echo "Keycloak еще не готов"
```

#### Импорт realm

1. **Получите административный токен Keycloak**:

```bash
KC_ADMIN="unicnet"  # или значение из переменной KEYCLOAK_ADMIN_USER
KC_PASS="unicnet"   # или значение из переменной KEYCLOAK_ADMIN_PASSWORD (можно прочитать из контейнера)
SERVER_IP="192.168.1.100"  # ваш IP адрес

ACCESS_TOKEN=$(curl -s -X POST "http://${SERVER_IP}:8095/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${KC_ADMIN}" \
  -d "password=${KC_PASS}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')
```

2. **Импортируйте realm**:

```bash
curl -X POST "http://${SERVER_IP}:8095/admin/realms" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @app/unicnet-realm.json
```

#### Создание пользователя через API

1. **Создайте пользователя**:

```bash
REALM="unicnet"  # имя realm
NEW_USER="unicadmin"
NEW_USER_PASS="your_password"
NEW_USER_EMAIL="unicadmin@local"

curl -X POST "http://${SERVER_IP}:8095/admin/realms/${REALM}/users" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${NEW_USER}\",
    \"email\": \"${NEW_USER_EMAIL}\",
    \"enabled\": true,
    \"emailVerified\": true
  }"
```

2. **Установите пароль пользователя**:

```bash
USER_ID=$(curl -s "http://${SERVER_IP}:8095/admin/realms/${REALM}/users?username=${NEW_USER}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.[0].id')

curl -X PUT "http://${SERVER_IP}:8095/admin/realms/${REALM}/users/${USER_ID}/reset-password" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"password\",
    \"value\": \"${NEW_USER_PASS}\",
    \"temporary\": false
  }"
```

3. **Добавьте пользователя в группы**:

```bash
# Получите ID групп
ADMIN_GROUP_ID=$(curl -s "http://${SERVER_IP}:8095/admin/realms/${REALM}/groups?search=unicnet_admin_group" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.[0].id')

# Добавьте пользователя в группу
curl -X PUT "http://${SERVER_IP}:8095/admin/realms/${REALM}/users/${USER_ID}/groups/${ADMIN_GROUP_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

> **Альтернативный способ через веб-интерфейс**: 
> - Откройте `http://<SERVER_IP>:8095` в браузере
> - Войдите с учетными данными администратора (KEYCLOAK_ADMIN / KEYCLOAK_ADMIN_PASSWORD)
> - Импортируйте realm через веб-интерфейс
> - Создайте пользователя и добавьте его в группы через веб-интерфейс

### Настройка Vault

> **Перед началом**: Убедитесь, что переменные `SERVER_IP`, `KC_ADMIN`, `KC_PASS`, `REALM` определены (см. раздел "Переменные окружения" выше)

#### Получение токена Vault

1. **Получите токен Vault** (требуется для создания секрета):

```bash
# Определите переменные, если они еще не заданы
SERVER_IP="192.168.1.100"  # ваш IP адрес
KC_ADMIN="unicnet"         # из переменной KEYCLOAK_ADMIN_USER (или прочитать из контейнера)
KC_PASS="unicnet"          # из переменной KEYCLOAK_ADMIN_PASSWORD (или прочитать из контейнера)
REALM="unicnet"            # имя realm

VAULT_TOKEN_ID="0f8e160416b94225a73f86ac23b9118b"
VAULT_USERNAME="UNFrontV2"

VAULT_TOKEN=$(curl -s "http://localhost:8200/api/token/${VAULT_TOKEN_ID}?username=${VAULT_USERNAME}" | jq -r '.token')
```

#### Создание секрета в Vault

Создайте секрет `UNFrontV2` с конфигурацией для frontend:

```bash
curl -X POST "http://localhost:8200/api/Secrets" \
  -H "accept: text/plain" \
  -H "Authorization: Bearer ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"UNFrontV2\",
    \"name\": \"UNFrontV2\",
    \"type\": \"Password\",
    \"data\": \"Empty\",
    \"metadata\": {
      \"api.keycloak.url\": \"http://${SERVER_IP}:8095/\",
      \"api.license.url\": \"http://unicnet.license\",
      \"api.backend.url\": \"http://${SERVER_IP}:30111/\",
      \"api.logger.url\": \"http://${SERVER_IP}:8082/\",
      \"api.syslog.url\": \"http://${SERVER_IP}:8001/\",
      \"KeyCloak.AdmUn\": \"${KC_ADMIN}\",
      \"KeyCloak.AdmPw\": \"${KC_PASS}\",
      \"KeyCloak.Realm\": \"${REALM}\"
    },
    \"tags\": [],
    \"expiresAt\": \"2050-12-31T23:59:59.999Z\"
  }"
```

> **Важно**: 
> - Убедитесь, что переменные `SERVER_IP`, `KC_ADMIN`, `KC_PASS`, `REALM` определены перед выполнением команды
> - Значения должны соответствовать экспортированным переменным окружения (KEYCLOAK_ADMIN_USER, KEYCLOAK_ADMIN_PASSWORD) или настройкам в контейнере Keycloak

<!-- TOC --><a name="-unicnet-2"></a>
### Настройка unicnet

<!-- TOC --><a name="--6"></a>
#### Перезапуск сервисов

После настройки Keycloak и Vault перезапустите backend сервис:

```bash
cd app
docker compose -f docker-compose.yml restart unicnet.backend
```

Проверьте логи контейнеров:

```bash
docker logs unicnet.backend
docker logs unicnet.frontend
docker logs unicnet.keycloak
```

<!-- TOC --><a name="-unicnet-3"></a>
#### Вход в unicnet

Откройте в браузере адрес приложения:

```
http://<SERVER_IP>:8080
```

Где `<SERVER_IP>` - внешний IP адрес вашего сервера.

Войдите с учетными данными пользователя, созданного в Keycloak:

![](./unicnet_assets/unicnet_auth.png "Страница авторизации Unicnet")

![](./unicnet_assets/unicnet_main_page.png "Страница главного меню Unicnet")#### Проверка подключения к RabbitMQ, Swagger, KeyCloak

Зайдите в админ-панель в правом верхнем углу. Проверьте корректность подключения к RabbitMQ, Swagger, KeyCloak:

![](./unicnet_assets/un_admin_panel.png "Страница авторизации Unicnet")

![](./unicnet_assets/un_settings_main.png "Настройки админ-панели. Главная")#### Создание подключений для SSH, TELNET, SNMP

Подключения — это учетные данные для авторизации на сетевых устройствах, необходимые для расширенного сбора информации о сетевых устройствах и работы автоматизированных задач Runbook. Для создания подключения заполните:

- Название
- Логин
- Пароль
- Суперпользователь (пароль суперпользователя, заполняется только для типа SSH)

> Суперпользователь (пароль суперпользователя, заполняется только для типа SSH)
>
> ![](./unicnet_assets/un_settings_cred.png "Настройки админ-панели. Credentials")
>
> ![](./unicnet_assets/un_cred_new.png "Настройки админ-панели. Новое подключение")

<!-- TOC --><a name="uninstall"></a>
## Деинсталляция (удаление)

### Автоматическая деинсталляция через скрипт

Если вы использовали скрипт `install.sh` для установки, вы можете использовать его же для удаления:

1. **Запустите скрипт**:

```bash
cd unicnet.enterprise
./install.sh
```

2. **Выберите опцию 13** - "Полная деинсталляция"

Скрипт выполнит следующие действия:
- Остановит и удалит все контейнеры
- Удалит все volumes (данные будут потеряны)
- Удалит Docker сеть `unicnet_network`
- Удалит Docker образы (опционально, с подтверждением)

> **Важно**: Деинсталляция удаляет только Docker-данные (контейнеры, volumes, сеть, образы). Файлы репозитория и конфигурационные файлы не удаляются.

### Ручная деинсталляция

Если вы выполняли ручную установку или хотите удалить вручную:

1. **Остановите и удалите контейнеры и volumes**:

```bash
cd app
docker compose -f docker-compose.yml down -v
```

2. **Удалите Docker сеть**:

```bash
docker network rm unicnet_network
```

3. **Удалите Docker образы** (опционально):

```bash
# Просмотрите список образов
docker images | grep cr.yandex

# Удалите образы вручную (замените на актуальные имена)
docker rmi cr.yandex/crp39psc34hg49unp6p7/postgres:alpine3.15
docker rmi cr.yandex/crp39psc34hg49unp6p7/mongo:4.4
docker rmi cr.yandex/crp39psc34hg49unp6p7/keycloak:22.0.5
docker rmi cr.yandex/crpi5ll6mqcn793fvu9i/unic/unicnetbackend:20251202101202
docker rmi cr.yandex/crpi5ll6mqcn793fvu9i/unicnet.solid/prod:front250826
# ... и другие образы
```

Или удалите все образы, связанные с проектом:

```bash
docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(cr.yandex|unicnet)" | xargs -r docker rmi
```

4. **Удалите volumes вручную** (если они остались):

```bash
# Просмотрите список volumes
docker volume ls | grep -E "(app_|unicnet)"

# Удалите volumes
docker volume rm <volume_name>
```

5. **Удалите конфигурационные файлы** (опционально):

```bash
# Удалите конфиг установщика (если использовали скрипт)
rm -f unicnet_installer.conf

# Удалите временные файлы
rm -f /tmp/unicnet-realm.resolved.json
```

6. **Удалите переменные окружения** (если они были экспортированы в текущей сессии):

Если вы экспортировали переменные окружения в текущей сессии терминала через `export`, они будут автоматически удалены при закрытии терминала. Однако, если переменные были добавлены в файлы конфигурации оболочки (`.bashrc`, `.bash_profile`, `.profile`, `.zshrc` и т.д.), их нужно удалить вручную:

```bash
# Проверьте, где определены переменные
grep -r "MONGO_" ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc 2>/dev/null
grep -r "KEYCLOAK_" ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc 2>/dev/null
grep -r "POSTGRES_" ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc 2>/dev/null

# Удалите строки с переменными из файлов конфигурации
# Например, для .bashrc:
sed -i '/^export MONGO_/d' ~/.bashrc
sed -i '/^export KEYCLOAK_/d' ~/.bashrc
sed -i '/^export POSTGRES_/d' ~/.bashrc

# Или отредактируйте файлы вручную
nano ~/.bashrc
```

**Для удаления переменных из текущей сессии**:

```bash
# Список переменных, которые нужно удалить
unset MONGO_INITDB_DATABASE
unset MONGO_UNICNET_DB
unset MONGO_UNICNET_USER
unset MONGO_UNICNET_PASSWORD
unset MONGO_LOGGER_DB
unset MONGO_LOGGER_USER
unset MONGO_LOGGER_PASSWORD
unset MONGO_VAULT_DB
unset MONGO_VAULT_USER
unset MONGO_VAULT_PASSWORD
unset KEYCLOAK_ADMIN
unset KEYCLOAK_ADMIN_PASSWORD
unset POSTGRES_USER
unset POSTGRES_PASSWORD
unset POSTGRES_DB

# Или удалите все переменные одной командой
unset $(env | grep -E "^(MONGO_|KEYCLOAK_|POSTGRES_)" | cut -d= -f1)
```

**Удаление конфигурационных файлов** (если нужно полностью удалить конфигурацию):

```bash
# Удалите конфигурационный файл установщика
rm -f unicnet_installer.conf

# Удалите временный файл realm (если есть)
rm -f /tmp/unicnet-realm.resolved.json

# Или удалите весь каталог app (если удаляете репозиторий)
rm -rf app
```

> **Предупреждение**: 
> - Удаление volumes приведет к потере всех данных (базы данных, конфигурации)
> - Удаление образов освободит место на диске, но их придется скачивать заново при следующей установке
> - Файлы репозитория (`unicnet.enterprise/`) не удаляются автоматически - удалите их вручную, если необходимо
> - Удаление переменных окружения из файлов конфигурации оболочки требует перезапуска терминала или выполнения `source ~/.bashrc`

### Полная очистка системы

Для полной очистки всех следов установки:

```bash
# 1. Остановите и удалите контейнеры
cd app
docker compose -f docker-compose.yml down -v

# 2. Удалите сеть
docker network rm unicnet_network 2>/dev/null || true

# 3. Удалите все volumes, связанные с проектом
docker volume ls --format "{{.Name}}" | grep -E "(app_|unicnet)" | xargs -r docker volume rm

# 4. Удалите все образы проекта
docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(cr.yandex|unicnet)" | xargs -r docker rmi -f

# 5. Удалите репозиторий (если нужно)
cd ..
rm -rf unicnet.enterprise

# 6. Удалите конфигурационные файлы
rm -f unicnet_installer.conf
rm -f /tmp/unicnet-realm.resolved.json

# 7. Удалите переменные окружения из текущей сессии
unset $(env | grep -E "^(MONGO_|KEYCLOAK_|POSTGRES_)" | cut -d= -f1) 2>/dev/null || true

# 8. Удалите переменные из файлов конфигурации оболочки (если они были добавлены)
sed -i '/^export MONGO_/d' ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc 2>/dev/null || true
sed -i '/^export KEYCLOAK_/d' ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc 2>/dev/null || true
sed -i '/^export POSTGRES_/d' ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc 2>/dev/null || true
```

<!-- TOC --><a name="faq"></a>
## F.A.Q

1. **Не создалась база данных в PostgreSQL при первом запуске**.Вы можете самостоятельно создать необходимую базу данных через контейнер. Просмотрите запущенные контейнеры. Выполните команду:

   ```bash
   docker ps
   ```

   Скопируйте `NAMES` контейнера PostgreSQL. Зайдите в контейнер PostgreSQL под root. Выполните команду:

   ```bash
   docker exec -u root -t -i 'container_name' /bin/bash
   ```

   Используя пользователя POSTGRES_USER, подключитесь к базе данных `postgres`. Выполните команду:

   ```bash
   psql -U <username> -d postgres
   ```

   Просмотрите список баз данных. Выполните команду:

   ```sql
   \l
   ```

   Если вашей базы данных нет, создайте её. Выполните команду:

   ```sql
   CREATE DATABASE dbname;
   ```




