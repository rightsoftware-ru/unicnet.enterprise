
## Инструкция по установке корпоративного мессенджера для общения и командной работы UnicChat

версия документа 1.7


### Оглавление

<!-- TOC --><a name="-pdf"></a>
### Скачать инструкции в PDF 

Инструкции для unicchat лежат в репозитории [docs](https://github.com/unicommorg/unicchat.enterprise/tree/main/docs)

* [Инструкция пользователя UnicChat.pdf](https://github.com/unicommorg/unicchat.enterprise/blob/main/docs/%D0%98%D0%BD%D1%81%D1%82%D1%80%D1%83%D0%BA%D1%86%D0%B8%D1%8F%20%D0%BF%D0%BE%D0%BB%D1%8C%D0%B7%D0%BE%D0%B2%D0%B0%D1%82%D0%B5%D0%BB%D1%8F%20UnicChat.pdf)
* [Инструкция_по_администрированию_UnicChat.pdf](https://github.com/unicommorg/unicchat.enterprise/blob/main/docs/%D0%98%D0%BD%D1%81%D1%82%D1%80%D1%83%D0%BA%D1%86%D1%8F_%D0%BF%D0%BE_%D0%B0%D0%B4%D0%BC%D0%B8%D0%BD%D0%B8%D1%81%D1%82%D1%80%D0%B8%D1%80%D0%BE%D0%B2%D0%B0%D0%BD%D0%B8%D1%8E_UnicChat.pdf)
* [Инструкция_по_лицензированию_UnicChat.pdf](https://github.com/unicommorg/unicchat.enterprise/blob/main/docs/%D0%98%D0%BD%D1%81%D1%82%D1%80%D1%83%D0%BA%D1%86%D1%8F_%D0%BF%D0%BE_%D0%BB%D0%B8%D1%86%D0%B5%D0%BD%D0%B7%D0%B8%D1%80%D0%BE%D0%B2%D0%B0%D0%BD%D0%B8%D1%8E_UnicChat.pdf)
* [Описание архитектуры UnicChat.pdf](https://github.com/unicommorg/unicchat.enterprise/blob/main/docs/%D0%9E%D0%BF%D0%B8%D1%81%D0%B0%D0%BD%D0%B8%D0%B5%20%D0%B0%D1%80%D1%85%D0%B8%D1%82%D0%B5%D0%BA%D1%82%D1%83%D1%80%D1%8B%20UnicChat.pdf)

<!-- TOC --><a name="-"></a>
### Архитектура установки

___

<!-- TOC --><a name="-1-"></a>
#### Установка на 1-м сервере

![](./assets/1vm-unicchat-install-scheme.jpg "Архитектура установки на 1-м сервере")

<!-- TOC --><a name="-2-"></a>
#### Установка на 2-х серверах (рекомендуется для промышленного использования)

![](./assets/2vm-unicchat-install-scheme.jpg "Архитектура установки на 2-х серверах")

<!-- TOC --><a name="--1"></a>
### Обязательные компоненты

___

<!-- TOC --><a name="push-"></a>
##### Push шлюз

Публичный сервис компании Unicomm. Подключение к нему необходимо для отправки push-сообщений на мобильные платформы Apple и Google.
Расположен во внешнем периметре на серверах компании. Серверу UnicChat требуются исходящие соединения к этому сервису и не требуются входящие соединения.

<!-- TOC --><a name="--2"></a>
##### ВКС шлюз

Публичный сервис компании Unicomm. Подключение к нему необходимо для работы аудио и видео конференций, а также аудио-звонков.
Расположены во внешнем периметре на серверах компании. Серверу UnicChat требуются исходящие соединения к этому сервису и не требуются входящие соединения.

<!-- TOC --><a name="-unicchat-1"></a>
##### Приложения UnicChat

Пользовательское приложение, установленное на iOS или Android платформе.
Сервер UnicChat должен иметь возможность принимать входящие сообщения от этих приложений, а также отправлять ответы.
Основное взаимодействие осуществляется через протокол HTTPS (443/TCP).
Для работы видео- и аудиозвонков необходимы протоколы STUN и TURN: входящие соединения на порты 7881/TCP и 7882/UDP, а также входящий и исходящий трафик UDP по портам 50000-60000 (RTP-трафик).

<!-- TOC --><a name="--3"></a>
### Опциональные компоненты

___

<!-- TOC --><a name="smtp-"></a>
##### SMTP сервер

Используется для отправки OTP-сообщений, восстановлений пароля, напоминания о пропущенных сообщениях, предоставляется вами.
Может быть использован как публичный, так и ваш собственный сервер. На схеме предполагается, что сервер находится в вашем сегменте DMZ.
**Интеграция с SMTP не является обязательным условием.**

<!-- TOC --><a name="ldap-"></a>
##### LDAP сервер

Используется для получения списка пользователей в системе. UnicChat может обслуживать как пользователей, заведенных в LDAP каталоге, так и внутренних пользователей в собственной базе. **Интеграция с LDAP не является обязательным условием**

<!-- TOC --><a name="-1--1"></a>
### Шаг 1. Подготовка окружения

<!-- TOC --><a name="11-"></a>
#### 1.1 Требования к конфигурации

<!-- TOC --><a name="-20-1-"></a>
##### Требования к конфигурации на 20 пользователей. Приложение и БД устанавливаются на 1-й виртуальной машине

<!-- TOC --><a name="--4"></a>
##### Конфигурация виртуальной машины

```
CPU 4 cores 1.7ghz, с набором инструкций FMA3, SSE4.2, AVX 2.0;
RAM 8 Gb;
150 Gb HDD\SSD;
```

<!-- TOC --><a name="-20-50-"></a>
##### Требования к конфигурации на 20-50 пользователей. Приложение и БД устанавливаются на разные виртуальные машины

<!-- TOC --><a name="--5"></a>
##### Конфигурация виртуальной машины для приложения

```
CPU 4 cores 1.7ghz, с набором инструкций FMA3, SSE4.2;
RAM 8 Gb;
200 Gb HDD\SSD
```

<!-- TOC --><a name="--6"></a>
##### Конфигурация виртуальной машины для БД

```
CPU 4 cores 1.7ghz, с набором инструкций FMA3, SSE4.2, AVX 2.0;
RAM 8 Gb;
100 Gb HDD\SSD
```

<!-- TOC --><a name="12-unicchat-solid-core"></a>
#### 1.2. Запрос лицензии для Unicchat Solid Core

Просим обратиться в компанию unicomm для выдачи лицензии Unicchat Solid Core

<!-- TOC --><a name="13-"></a>
#### 1.3. Установка сторонних зависимостей

Для ОС Ubuntu 20+ предлагаем воспользоваться нашими краткими инструкциями. Для других ОС воспользуйтесь инструкциями, размещенными в сети Интернет.

1. Установить `docker` и `docker-compose`
2. Установить `nginx`.
3. Установить `certbot` и плагин `python3-certbot-nginx`.
4. Установить `git`. 
5. Авторизоваться в yandex container registry для скачивания образов
```bash
sudo docker login \
  --username oauth \
  --password y0_AgAAAAB3muX6AATuwQAAAAEawLLRAAB9TQHeGyxGPZXkjVDHF1ZNJcV8UQ \
  cr.yandex
```

<!-- TOC --><a name="14-"></a>
#### 1.4. Клонирование репозитория

1. Скачать при помощи `git` командой `git clone` файлы по https://github.com/unicommorg/unicchat.enterprise.git.
 Выполнить на сервере

```shell
git clone https://github.com/unicommorg/unicchat.enterprise.git
```



<!-- TOC --><a name="-2-nginx"></a>
### Шаг 2. Настройка NGINX

<!-- TOC --><a name="21-dns-"></a>
#### 2.1 Зарегистрировать DNS имена

Перед началом работы запросите DNS-имена. Ниже приведены DNS-имена для примера. Вы можете изменить их под свои нужды.

* myapp.unic.chat
* myminio.unic.chat (требуется настройка в /etc/hosts на сервере с NGINX)
* myedt.unic.chat (требуется настройка в /etc/hosts на сервере с NGINX)
* mylk-yc.unic.chat
* turn.mylk-yc.unic.chat
* whip.mylk-yc.unic.chat

1. **myapp.unic.chat**

   **Назначение**: Основной адрес сервера приложений UnicChat, через который пользователи получают доступ к веб-интерфейсу мессенджера.  
   **Использование**: Обеспечивает доступ к клиентскому интерфейсу UnicChat, включая чаты, настройки и администрирование. Используется для HTTPS-соединений и проверки работоспособности сервиса.

2. **myminio.unic.chat**

   **Назначение**: Адрес сервера MinIO, используемого для хранения файлов (S3-совместимое хранилище).  
   **Использование**: Хранит файлы, загружаемые пользователями, и документы DocumentServer. Консоль управления доступна через http://<hostname minio>:9002 (логин: minioadmin, пароль: rootpassword). Бакет uc.onlyoffice.docs создаётся для документов.  
   **Настройка в /etc/hosts**: Требуется. Необходимо добавить запись в /etc/hosts на сервере с NGINX, например: `10.0.XX.XX myminio.unic.chat`, где `10.0.XX.XX` — IP-адрес сервера.

3. **myedt.unic.chat**

   **Назначение**: Адрес сервера DocumentServer, используемого для редактирования документов в UnicChat.  
   **Использование**: Обеспечивает интеграцию с DocumentServer для совместной работы с документами. Доступен через https://myedt.unic.chat.  
   **Настройка в /etc/hosts**: Требуется. Необходимо добавить запись в /etc/hosts на сервере с NGINX, например: `10.0.XX.XX myedt.unic.chat`, где `10.0.XX.XX` — IP-адрес сервера.

4. **mylk-yc.unic.chat**

   **Назначение**: Адрес ВКС-шлюза (видеоконференцсвязи), используемого для аудио- и видеозвонков.  
   **Использование**: Обеспечивает функциональность видеоконференций в UnicChat. Требует исходящих соединений для клиентских приложений и настройки STUN/TURN для NAT-траверсала.

5. **turn.mylk-yc.unic.chat**

   **Назначение**: Адрес TURN-сервера, используемого для обхода NAT при видеозвонках.  
   **Использование**: Обеспечивает стабильное соединение для видеоконференций в сетях с ограничениями (например, за NAT). Работает в связке с ВКС-шлюзом.

6. **whip.mylk-yc.unic.chat**

   **Назначение**: Адрес WHIP-сервера (WebRTC-HTTP Ingestion Protocol), используемого для потоковой передачи медиа в видеоконференциях.  
   **Использование**: Поддерживает передачу медиа-данных в реальном времени для видеозвонков.

**Примечания**

DNS адреса `myminio.unic.chat` и `myedt.unic.chat` требуют явной настройки в файле `/etc/hosts` на сервере с NGINX. Пример записи:  
* `10.0.XX.XX myminio.unic.chat`  
* `10.0.XX.XX myedt.unic.chat`

Замените `10.0.XX.XX` на актуальный IP-адрес вашего NGINX сервера.

<!-- TOC --><a name="22-nginx"></a>
#### 2.2 Провести настройку Nginx

<!-- TOC --><a name="221-nginx"></a>
##### 2.2.1 Установить nginx

```bash
sudo apt update
sudo apt install nginx -y
```

<!-- TOC --><a name="222-unicchat"></a>
##### 2.2.2 Настроить nginx конфигурацию для Unicchat и Базы знаний

В директории ./nginx лежат шаблоны для конфигурации для nginx.
Переделайте значения upstream под свою конфигурацию.
В upstream укажите адрес и порт на который будет работать контейнер с приложением 

Порты по умолчанию 
* для myapp.unic.chat - 8080
* для myedt.unic.chat - 8880
* для myminio.unic.chat - 9000


.

<!-- TOC --><a name="225-certbot-"></a>
##### 2.2.5 Установка certbot и получение сертификата

Установить certbot по этой инструкции: https://certbot.eff.org/instructions?ws=nginx&os=debianbuster

Запросить ssl  сертификаты 
```shell
sudo certbot certonly --standalone -d myminio.unic.chat  
sudo certbot certonly --standalone -d myedtapp.unic.chat
sudo certbot certonly --standalone -d myapp.unic.chat

``` 
<!-- TOC --><a name="223-nginx"></a>
##### 2.2.3 Подготовка сайта nginx

* Активировать конфигурацию 
`sudo ln -s /etc/nginx/sites-available/myapp.unic.chat /etc/nginx/sites-enabled/myapp.unic.chat`
`sudo ln -s /etc/nginx/sites-available/myedtapp.unic.chat/etc/nginx/sites-enabled/myedtapp.unic.chat`
`sudo ln -s /etc/nginx/sites-available/myminio.unic.chat t /etc/nginx/sites-enabled/myminio.unic.chat `

* Деактивировать конфигурацию по-умолчанию
`sudo rm /etc/nginx/sites-enabled/default`

* Проверить корректность конфигураций 
`sudo nginx -t`

Результат:
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

* Перезапустить nginx
`sudo systemctl restart nginx.service`


<!-- TOC --><a name="226-certbot"></a>
##### 2.2.6 Настройка автоматической проверки сертификата certbot

Добавить правила проверки сертификата, например, в 7-00 каждый день, в `/etc/cron.daily/certbot`

`00 7 * * * certbot renew --post-hook "systemctl reload nginx"`



<!-- TOC --><a name="23-"></a>
#### 2.3 Открыть доступы до внутренних ресурсов

<!-- TOC --><a name="-unicchat-2"></a>
##### Входящие соединения на стороне сервера UnicChat:

Открыть порты:

- 8080/TCP - по-умолчанию, сервер запускается на 8080 порту и доступен http://localhost:8080, где localhost - это IP адрес сервера UnicChat;
- 443/TCP - порт будет нужен, если вы настроили nginx с сертификатом HTTPS;

<!-- TOC --><a name="-unicchat-3"></a>
##### Исходящие соединения на стороне сервера UnicChat на push:

* Открыть доступ для Push-шлюза:
 * 443/TCP, на хост **push1.unic.chat**;


##### Исходящие соединения на стороне сервера UnicChat на ВКС:
Примечание **lk-yc.unic.chat** адрес внешней ВКС компании `Unicomm`, при развертывание локального медиа сервера используйте свой адрес.
* Открыть доступ для ВКС сервера:
 * 443/TCP, на хост **lk-yc.unic.chat**;
 * 7881/TCP, 7882/UDP
 * (50000 - 60000)/UDP (диапазон этих портов может быть изменён при развертывании лицензионной версии непосредственно владельцем лицензии)

* Открыть доступ до внутренних ресурсов: LDAP, SMTP, DNS при необходимости использования этого функционала


<!-- TOC --><a name="-3-"></a>
### Шаг 3. Установка локального медиа сервера для ВКС

<!-- TOC --><a name="31-"></a>
#### 3.1 Порядок установки сервера

Перейдите в директорию vcs.unic.chat.template.
1. В файле `.env` указать домены на которых будет работать ВСК сервер. WHIP пока не обязателен и его можно пропустить.
2. Запустить `./install_server.sh` (возможно, на последнюю операцию в файле нужно sudo). Перед запуском убедиться, что в директории, где запускается скрипт, есть файл `.env`. Сервер будет установлен в текущей поддиректории `./unicomm-vcs`.
3. Если на сервере отсутствует docker, то выполнить скрипт под sudo `./install_docker.sh` (только для Ubuntu) или иным способом установить docker + compose.
4. Можно не использовать caddy, вместо этого использовать nginx. конфигурация сайтов в файле `example.sites.nginx.md`. На домены нужны HTTPS сертификаты. (плохо работает с TUNE сервером, лучше не использовать в продакш)
5. В файле ./unicomn-vcs/egress.yaml при необходимости отредактируйте значения api_key и api_secret
```yml
api_key: 
api_secret: 
ws_url: wss://
```

6. Запустите медиасервер командой `docker compose -f ./unicomm-vcs/docker-compose.yml up -d`.
7. Проверка поднятого сервера утилитой livekit-test: https://livekit.io/connection-test 
token: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NzUzNzgxOTEsImlzcyI6IkFQSUZCNnFMeEtKRFc3VCIsIm5hbWUiOiJUZXN0IFVzZXIiLCJuYmYiOjE3MzkzNzgxOTEsInN1YiI6InRlc3QtdXNlciIsInZpZGVvIjp7InJvb20iOiJteS1maXJzdC1yb29tIiwicm9vbUpvaW4iOnRydWV9fQ.20rviVegoNerAE_WiFxshYDpL2DVAHvnJzkjsV3L_0Y`

<!-- TOC --><a name="32-"></a>
#### 3.2 Проверка открытия портов

1. Страница с открытыми портами: https://docs.livekit.io/home/self-hosting/ports-firewall/#ports
2. 
```shell
sudo lsof -i:7880 -i:7881 -i:5349 -i:3478 -i:50879 -i:54655 -i:59763
COMMAND    PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
livekit-s 5780 root    8u  IPv6  69483      0t0  TCP *:7881 (LISTEN)
livekit-s 5780 root    9u  IPv4  69493      0t0  TCP *:5349 (LISTEN)
livekit-s 5780 root   10u  IPv4  69494      0t0  UDP *:3478
livekit-s 5780 root   11u  IPv6  70260      0t0  TCP *:7880 (LISTEN)
```
```shell
telnet `internal_IP` 7880 # 7880 7881 5349
```

<!-- TOC --><a name="-4-unicchat"></a>
### Шаг 4. Развертывание базы знаний для UNICCHAT

Перейдите в директорию knowledgebase

<!-- TOC --><a name="41-"></a>
#### 4.1 Подготовка сервера




<!-- TOC --><a name="44-minio-s3"></a>
#### 4.4 Развертывание MinIO S3

<!-- TOC --><a name="441-knowledgebaseminio"></a>
##### 4.4.1 Перейдите в директорию knowledgebase/

В файле `knowledgebase.env` 
По своему желанию вы можете изменить значения переменных, или не менять их.
Запомните значения MINIO_ROOT_USER и MINIO_ROOT_PASSWORD,  они необходимы для настройки интеграции `Базы Знаний` и `UnicChat`.

```yml
MINIO_ROOT_USER
MINIO_ROOT_PASSWORD
DB_NAME
DB_USER

```

<!-- TOC --><a name="442-minio"></a>
##### 4.4.2 Запустите Базу Знаний

```bash
docker -f minio/docker-compose up -d && docker -f Docker-DocumentServer/docker-compose up -d  
```

<!-- TOC --><a name="443-minio"></a>
##### 4.4.3 Доступ к MinIO:

Консоль: http://ваш_сервер:9002
логин и пароль указан в `knowledgebase.env` файле
```yml
MINIO_ROOT_USER:
MINIO_ROOT_PASSWORD:
```

<!-- TOC --><a name="444-bucket"></a>
##### 4.4.4 Создание bucket

Создайте bucket `uc.onlyoffice.docs` и настройках bucket назначьте Access Policy:public.

S3 Endpoint: http://ваш_сервер:9000





<!-- TOC --><a name="--12"></a>


<!-- TOC --><a name="-5-unicchat"></a>
### Шаг 5. Установка UnicChat

<!-- TOC --><a name="51-mongodb"></a>
#### 5.1  Настройка Unic.Chat

1. [Linux] На сервере БД выполните команду `grep avx /proc/cpuinfo`. Если в ответе вы не видите AVX, то вам лучше выбрать версию mongodb < 5.х, например, 4.4
 если AVX на вашем сервере поддерживается, рекомендуется выбрать версию mongodb > 5.х.
2. ВАЖНО! Если вы планируете запустить БД и сервер UnicChat на разных виртуальных серверах, то в параметрах `MONGODB_INITIAL_PRIMARY_HOST` и `MONGODB_ADVERTISED_HOSTNAME` вам нужно указать адрес (DNS или IP) вашего сервера, где запускается БД.
3. Если же установка планируется на одной машине, создайте вначале сети в которые будут подключаться контейнеры приложения и БД
unicchat-backend для unic.chat.solid и unic.chat.db.mongo
nicchat-frontend для unic.chat.appserver и unic.chat.db.mongo
```shell
docker network create unicchat-backend
docker network create unicchat-frontend
```
4. Измените по своему усмотрению значения переменных окружения.
Обязательно вставье значения в UNIC_LICENSE=
``` shell
nano multi_server_install/env/multi_server_env.env
```


Запустите скрипт 
``` shell

chmod +x multi_server_install/update_multi_server_env.sh
cd multi_server_install
./update_multi_server_env.sh
cd ..
```

Звпустите контейнеры 
``` shell

docker compose -f multi_server_install/mongodb.yml up -d && docker compose -f multi_server_install/unic.chat.solid.yml up -d && docker compose multi_server_install/unic.chat.appserver.yml up -d
```

<!-- TOC --><a name="52-"></a>
#### 5.2 Создать базу и пользователя для подключения к базе

1. После того как база успешно запустилась, подключимся к контейнеру с запущенной БД. Для этого на сервере, где запущен docker контейнер c базой, выполните

```shell
docker exec -it unic.chat.db.mongo mongosh -u root -p "rootpassword"
```
где `unic.chat.db.mongo` - имя нашего контейнера, указанного в `multi_server_install/mongodb.yml`, пароль MONGODB_ROOT_PASSWORD  в `multi_server_install/mongodb_env.env`


``` javascript
// проверьте наличие вашей базы данных
show databases
```

```javascript
// Перейдите на вашу базу данных и проверьте пользователя
use unicchat_db
show users
```
```javascript
db.updateUser( "unicchat_admin",
{
roles: [
{role: "readWrite", db: "local"},
{role: "readWrite", db: "unicchat_db"},
{role: "dbAdmin", db: "unicchat_db"},
{role: "clusterMonitor", db: "admin"}
]
})

```javascript
// Перейдите на вашу базу данных и проверьте права пользователя
use unicchat_db
show users
```
##### 2.2.7 Настройка Unicchat для работы с HTTPS

Провести настройку для обхода работы CORS в приложение для HTTPS, для этого в базе выполнить c вашим dns именем:

``` javascript
db.rocketchat_settings.updateOne({"_id":"Site_Url"},{"$set":{"value":'https://myapp.unic.chat'}}) 
db.rocketchat_settings.updateOne({"_id":"Site_Url"},{"$set":{"packageValue":'https://myapp.unic.chat'}})
```

Сайт открывается https://myapp.unic.chat
Если сайт сразу не открывается, то для сброса кеша использовать очистку кеша и cookie браузера, ctrl+R или использовать безопасный режим браузера.


<!-- TOC --><a name="-6-"></a>
### Шаг 6. Создание пользователя администратора

* `Name` - Имя пользователя, которое будет отображаться в чате;
* `Username` - Логин пользователя, который вы будете указывать для авторизации;
* `Email` - Действующая почта, используется для восстановления
* `Organization Name` - Краткое название вашей организации латинскими буквами без пробелов и спец. символов, используется для регистрации push уведомлений. Может быть указан позже;
* `Organization ID` - Идентификатор вашей организации, используется для подключения к push серверу. Может быть указан позже. Для получения ID необходимо написать запрос с указанием значения в Organization Name на почту support@unicomm.pro;
* `Password` - пароль вашего пользователя;
* `Confirm your password` - подтверждение пароля;

1. После создания пользователя, авторизоваться в веб-интерфейсе с использованием ранее указанных параметров.
2. Для включения пушей, перейти в раздел Администрирование - Push. Включить использование шлюза и указать адрес шлюза https://push1.unic.chat
3. Перейти в раздел Администрирование - Organization, убедиться что поля заполнены в соответствии с вашими данными.
4. Настройка завершена.

При первом входе может возникнуть информационное предупреждение
![](./assets/111.jpg "Предупреждение при первом входе")

Нажмите "ДА"

<!-- TOC --><a name="-7-push-"></a>
### Шаг 7. Настройка push-уведомлений

Приложение Unicchat работает с внешним push сервером для доставки push-уведомлений в приложение Unicchat на мобильные устройства.

#### Клиентские приложения

* [Репозитории клиентских приложений]
* Android: (https://play.google.com/store/apps/details?id=pro.unicomm.unic.chat&pcampaignid=web_share)
* iOS: (https://apps.apple.com/ru/app/unicchat/id1665533885)
* Desktop: (https://github.com/unicommorg/unic.chat.desktop.releases/releases)



