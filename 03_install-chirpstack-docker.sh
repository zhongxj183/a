#!/bin/bash
set -e


# 定义常量
CHIRPSTACK_DIR="/data/chirpstack-docker-v4"
MOSQUITTO_CONFIG_DIR="${CHIRPSTACK_DIR}/configuration/mosquitto/config"
MOSQUITTO_CERTS_DIR="${CHIRPSTACK_DIR}/configuration/mosquitto/certs"
MQTT_USERNAME="neuron"
MQTT_PASSWORD="neuron@123"
SERVER_IP="192.168.176.205"
SERVER_DNS="mqtts.local"



# 检测Linux系统的发行版本
if [ -f /etc/redhat-release ]; then
    PACKAGE_MANAGER="yum"
elif [ -f /etc/debian_version ]; then
    PACKAGE_MANAGER="apt-get"
else
    echo "Unsupported Linux distribution"
    exit 1
fi

# 安装unzip
if command -v unzip >/dev/null 2>&1; then
    echo "Unzip is already installed. Skipping installation."
else
    echo "Installing Unzip..."
    if [ "${PACKAGE_MANAGER}" == "yum" ]; then
        yum install -y unzip >/dev/null 2>&1
    elif [ "${PACKAGE_MANAGER}" == "apt-get" ]; then
        apt-get update >/dev/null 2>&1
        apt-get install -y unzip >/dev/null 2>&1
    else
        echo "Unsupported Linux distribution"
        exit 1
    fi
fi

# 下载并解压 chirpstack-docker
mkdir -p /data && cd /data
if ! wget https://codeload.github.com/chirpstack/chirpstack-docker/zip/refs/heads/master -O chirpstack-docker-master.zip; then
    echo "Failed to download chirpstack-docker"
    exit 1
fi
if ! unzip -q chirpstack-docker-master.zip; then
    echo "Failed to unzip chirpstack-docker"
    exit 1
fi
mv chirpstack-docker-master chirpstack-docker-v4

# 创建必要的目录
mkdir -p "${MOSQUITTO_CONFIG_DIR}" "${MOSQUITTO_CERTS_DIR}"

# 创建 Mosquitto 配置文件
cat << EOF > "${MOSQUITTO_CONFIG_DIR}/mosquitto.conf"
listener 1883
allow_anonymous false
password_file /mosquitto/config/pwfile
use_identity_as_username true
listener 8883
cafile /mosquitto/certs/ca.crt
certfile /mosquitto/certs/server.crt
keyfile /mosquitto/certs/server.key
EOF

# 生成mqtt密文密码
MQTT_PASSWORD_ENCRYPT=$(docker run --rm -it eclipse-mosquitto:2 /bin/sh -c "touch pw.txt && chmod 700 pw.txt && mosquitto_passwd -b pw.txt ${MQTT_USERNAME} ${MQTT_PASSWORD} && cat pw.txt")

# 创建 Mosquitto 用户密码文件
echo "${MQTT_PASSWORD_ENCRYPT}" > "${MOSQUITTO_CONFIG_DIR}/pwfile"

# 生成证书函数
generate_certificates() {
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -sha256 \
      -keyout ca.key -out ca.crt -subj '/CN=neuron' \
      -config <(cat /etc/ssl/openssl.cnf; printf "[SAN]\nsubjectAltName=IP:${SERVER_IP},DNS:${SERVER_DNS}")

    # 生成服务端的私钥和证书  
    openssl genrsa -out server.key 2048
    openssl req -new -sha256 -key server.key -out server.csr \
      -subj '/CN=neuron' \
      -reqexts SAN -config <(cat /etc/ssl/openssl.cnf; printf "\n[SAN]\nsubjectAltName=IP:${SERVER_IP},DNS:${SERVER_DNS}")
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
      -out server.crt -days 3650 -sha256 -extfile <(printf "subjectAltName=IP:${SERVER_IP},DNS:${SERVER_DNS}")

    # 生成client端的私钥和证书
    openssl genrsa -out client.key 2048
    openssl req -new -sha256 -key client.key -out client.csr -subj '/CN=neuron'
    openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
      -out client.crt -days 3650 -sha256
}

# 生成证书
cd "${MOSQUITTO_CERTS_DIR}"
generate_certificates

# 创建 Docker Compose 文件
cd "${CHIRPSTACK_DIR}"
cat << 'EOF' > docker-compose.yml
version: "3"

services:
  chirpstack:
    image: chirpstack/chirpstack:4
    command: -c /etc/chirpstack
    restart: unless-stopped
    volumes:
      - ./configuration/chirpstack:/etc/chirpstack
      - ./lorawan-devices:/opt/lorawan-devices
    depends_on:
      - postgres
      - mosquitto
      - redis
    environment:
      - MQTT_BROKER_HOST=mosquitto
      - REDIS_HOST=redis
      - POSTGRESQL_HOST=postgres
    ports:
      - 8080:8080

  chirpstack-gateway-bridge-as923:
    image: chirpstack/chirpstack-gateway-bridge:4
    restart: unless-stopped
    ports:
      - 1700:1700/udp
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge
    environment:
      - INTEGRATION__MQTT__EVENT_TOPIC_TEMPLATE=as923/gateway/{{ .GatewayID }}/event/{{ .EventType }}
      - INTEGRATION__MQTT__STATE_TOPIC_TEMPLATE=as923/gateway/{{ .GatewayID }}/state/{{ .StateType }}
      - INTEGRATION__MQTT__COMMAND_TOPIC_TEMPLATE=as923/gateway/{{ .GatewayID }}/command/#
    depends_on:
      - mosquitto

  chirpstack-gateway-bridge-cn470:
    image: chirpstack/chirpstack-gateway-bridge:4
    restart: unless-stopped
    ports:
      - 1701:1700/udp
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge
    environment:
      - INTEGRATION__MQTT__EVENT_TOPIC_TEMPLATE=cn470_1/gateway/{{ .GatewayID }}/event/{{ .EventType }}
      - INTEGRATION__MQTT__STATE_TOPIC_TEMPLATE=cn470_1/gateway/{{ .GatewayID }}/state/{{ .StateType }}
      - INTEGRATION__MQTT__COMMAND_TOPIC_TEMPLATE=cn470_1/gateway/{{ .GatewayID }}/command/#
    depends_on:
      - mosquitto

  chirpstack-gateway-bridge-eu868:
    image: chirpstack/chirpstack-gateway-bridge:4
    restart: unless-stopped
    ports:
      - 1702:1700/udp
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge
    environment:
      - INTEGRATION__MQTT__EVENT_TOPIC_TEMPLATE=eu868/gateway/{{ .GatewayID }}/event/{{ .EventType }}
      - INTEGRATION__MQTT__STATE_TOPIC_TEMPLATE=eu868/gateway/{{ .GatewayID }}/state/{{ .StateType }}
      - INTEGRATION__MQTT__COMMAND_TOPIC_TEMPLATE=eu868/gateway/{{ .GatewayID }}/command/#
    depends_on:
      - mosquitto

  chirpstack-gateway-bridge-basicstation-as923:
    image: chirpstack/chirpstack-gateway-bridge:4
    restart: unless-stopped
    command: -c /etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge-basicstation-as923.toml
    ports:
      - 3001:3001
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge
    depends_on:
      - mosquitto

  chirpstack-gateway-bridge-basicstation-cn470:
    image: chirpstack/chirpstack-gateway-bridge:4
    restart: unless-stopped
    command: -c /etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge-basicstation-cn470_1.toml
    ports:
      - 3002:3001
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge
    depends_on:
      - mosquitto

  chirpstack-gateway-bridge-basicstation-eu868:
    image: chirpstack/chirpstack-gateway-bridge:4
    restart: unless-stopped
    command: -c /etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge-basicstation-eu868.toml
    ports:
      - 3003:3001
    volumes:
      - ./configuration/chirpstack-gateway-bridge:/etc/chirpstack-gateway-bridge
    depends_on:
      - mosquitto

  chirpstack-rest-api:
    image: chirpstack/chirpstack-rest-api:4
    restart: unless-stopped
    command: --server chirpstack:8080 --bind 0.0.0.0:8090 --insecure
    ports:
      - 8090:8090
    depends_on:
      - chirpstack

  postgres:
    image: postgres:14-alpine
    restart: unless-stopped
    volumes:
      - ./configuration/postgresql/initdb:/docker-entrypoint-initdb.d
      - postgresqldata:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=chirpstack
      - POSTGRES_PASSWORD=chirpstack
      - POSTGRES_DB=chirpstack

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    command: redis-server --save 300 1 --save 60 100 --appendonly no
    volumes:
      - redisdata:/data

  mosquitto:
    image: eclipse-mosquitto:2
    restart: unless-stopped
    ports:
      - 1883:1883
      - 8883:8883
    volumes:
      - ./configuration/mosquitto/config/:/mosquitto/config/
      - ./configuration/mosquitto/certs/:/mosquitto/certs/

volumes:
  postgresqldata:
  redisdata:
EOF

# 修改 chirpstack.toml 文件
sed -i 's/cn470_10/cn470_0/g' configuration/chirpstack/chirpstack.toml
sed -i '/cn470_0/a\    "cn470_1",' configuration/chirpstack/chirpstack.toml
sed -i "/json=true/a\    password=\"${MQTT_PASSWORD}\"" configuration/chirpstack/chirpstack.toml
sed -i "/json=true/a\    username=\"${MQTT_USERNAME}\"" configuration/chirpstack/chirpstack.toml

# 添加额外的网络通道
cat << EOF >> configuration/chirpstack/region_as923.toml

    [[regions.network.extra_channels]]
    frequency=922000000
    min_dr=0
    max_dr=5

    [[regions.network.extra_channels]]
    frequency=922200000
    min_dr=0
    max_dr=5

    [[regions.network.extra_channels]]
    frequency=922400000
    min_dr=0
    max_dr=5

    [[regions.network.extra_channels]]
    frequency=922600000
    min_dr=0
    max_dr=5

    [[regions.network.extra_channels]]
    frequency=922800000
    min_dr=0
    max_dr=5

    [[regions.network.extra_channels]]
    frequency=923000000
    min_dr=0
    max_dr=5
EOF

# 更新配置文件中的用户名和密码
update_config() {
    local config_file=$1
    sed -i "s/username=\"\"/username=\"${MQTT_USERNAME}\"/g" "${config_file}"
    sed -i "s/password=\"\"/password=\"${MQTT_PASSWORD}\"/g" "${config_file}"
}

for file in configuration/chirpstack/region*; do 
   update_config "${file}"
done

for file in configuration/chirpstack-gateway-bridge/chirpstack-gateway-bridge*; do 
   update_config "${file}"
done

# 启动 chirpstack 服务
docker compose up -d

# 创建 systemd 服务
cat << EOF > /etc/systemd/system/chirpstack.service
[Unit]
Description=chirpstack-v4
After=docker.service
Requires=docker.service
Documentation=https://www.chirpstack.io/docs/

[Service]
Type=simple
Restart=on-failure
RestartSec=5
ExecStart=/usr/bin/docker compose -f ${CHIRPSTACK_DIR}/docker-compose.yml up
ExecStop=/usr/bin/docker compose -f ${CHIRPSTACK_DIR}/docker-compose.yml down

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
chmod +x /etc/systemd/system/chirpstack.service
systemctl enable chirpstack.service --now
systemctl status chirpstack.service

