# Схема взаимодействия служб

## Оглавление

- [Работа приложения](#runtime)
- [Подготовка и проверка](#startup)
- [Четыре варианта](#variants)

<a id="runtime"></a>
## Работа приложения

```mermaid
flowchart LR
  U[Пользователь] -->|HTTP 8080| F[Frontend]
  F --> B[Backend]
  F --> R[Router]
  F --> S[SysLog]
  F --> L[Logger]
  F --> V[Vault]
  R --> B
  R --> S
  R --> L
  B --> L
  B --> K[Keycloak]
  R --> K
  B --> P[(PostgreSQL)]
  S --> P
  L --> P
  V --> P
  K -. Только встроенный Keycloak .-> P
  B -. Настройки .-> V
  R -. Настройки .-> V
  S -. Настройки .-> V
  L -. Настройки .-> V
  R -->|Опрос и управление| D[Сетевые устройства]
  D -->|Сообщения Syslog| S
```

Frontend предоставляет интерфейс. Backend обрабатывает запросы и проверяет права через Keycloak. Router работает с устройствами, SysLog принимает сообщения устройств, Logger хранит журналы. Vault выдаёт настройки служб. PostgreSQL хранит данные приложений. Имена узлов обозначают службы, а не конкретные серверы.

Внешний Keycloak использует собственную инфраструктуру хранения. Его база не обязана совпадать с базой UnicNet; связь Keycloak → PostgreSQL на схеме относится только к встроенному Keycloak.

<a id="startup"></a>
## Подготовка и проверка

```mermaid
flowchart TD
  A[prepare: лицензия и генерация секретов] --> P[PostgreSQL: встроенный или внешний]
  P --> D[database: проверка выделенной базы]
  D --> V[Vault: запуск с закрытым bootstrap]
  D --> K[Встроенный Keycloak: запуск]
  V --> I[init: настройка Vault и проверка Keycloak]
  K --> I
  E[Внешний Keycloak: готов заранее] -. Внешний вариант .-> I
  I --> L[Logger]
  L --> R[Router и SysLog]
  R --> B[Backend]
  B --> F[Frontend]
  F --> T[verify: HTTP, вход, закрытый bootstrap]
```

Задания prepare/database/init/verify запускаются из готового образа unicnetinit и завершаются с кодом 0. Остальные службы работают постоянно. Связи на второй схеме показывают порядок готовности, а не сетевые запросы. При встроенном PostgreSQL база стартует после prepare; внешний PostgreSQL и внешний Keycloak готовит администратор до установки.

<a id="variants"></a>
## Четыре варианта

1. Все службы встроены: `compose.yml` + `compose.pg.yml` + `compose.keycloak.yml`.
2. Внешний PostgreSQL: `compose.yml` + `compose.keycloak.yml`.
3. Внешний Keycloak: `compose.yml` + `compose.pg.yml`.
4. Обе службы внешние: только `compose.yml`.

Готовые настройки выбора описаны в [основной инструкции](../README.md#variants). Docker Compose сам создаёт внутреннюю сеть. Подключения к существующим службам задаются в infrastructure.json.
