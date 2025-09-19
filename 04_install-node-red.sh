#!/bin/bash
set -e

# 定义常量
NODE_RED_SERVICE="/etc/systemd/system/node-red.service"
NODE_RED_DIR="/root/.node-red"
NODE_RED_BACKUP_DIR="/data/nodered-backup"
USERNAME="neuron"  # 用户名
PASSWORD="neuron@123"  # 密码

# 检测操作系统类型
if [ -f /etc/redhat-release ]; then
    PACKAGE_MANAGER="yum"
    NODESOURCE_SETUP_URL="https://rpm.nodesource.com/setup_20.x"
elif [ -f /etc/debian_version ]; then
    PACKAGE_MANAGER="apt-get"
    NODESOURCE_SETUP_URL="https://deb.nodesource.com/setup_20.x"
else
    echo "Unsupported Linux distribution"
    exit 1
fi

# 安装必要的依赖
if [ "${PACKAGE_MANAGER}" == "yum" ]; then
    yum install -y curl gcc-c++ make
elif [ "${PACKAGE_MANAGER}" == "apt-get" ]; then
    apt-get update
    apt-get install -y curl build-essential
fi

# 安装 Node.js（Node-RED 的依赖）
curl -fsSL ${NODESOURCE_SETUP_URL} | bash -
if [ "${PACKAGE_MANAGER}" == "yum" ]; then
    yum install -y nodejs
elif [ "${PACKAGE_MANAGER}" == "apt-get" ]; then
    apt-get install -y nodejs
fi

# 使用 npm 安装 Node-RED
npm install -g --unsafe-perm node-red node-red-admin

# 创建 systemd 服务文件
cat << EOF > ${NODE_RED_SERVICE}
[Unit]
Description=Node-RED
Documentation=https://nodered.org/docs/
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/node-red
Restart=on-failure
RestartSec=10
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# 启动 Node-RED 服务并设置为开机自启
systemctl daemon-reload
systemctl enable node-red
systemctl start node-red
sleep 5

# 生成密码哈希
HASHED_PASSWORD=$(node-red-admin hash-pw <<< "${PASSWORD}" | awk '{print $2}')

# 修改settings.js文件，开启密码认证
cp "${NODE_RED_DIR}/settings.js" "${NODE_RED_DIR}/settings.js.bak"
sed -i "/adminAuth:/i \
\     adminAuth: {\n\
        type: \"credentials\",\n\
        users: [{\n\
            username: \"${USERNAME}\",\n\
            password: \"${HASHED_PASSWORD}\",\n\
            permissions: \"*\"\n\
        }]\n\
    },\n\
" "${NODE_RED_DIR}/settings.js"

# 重新启动 Node-RED
systemctl stop node-red
systemctl start node-red

# 显示 Node-RED 服务状态
systemctl status node-red

# 定时备份脚本
mkdir -p $NODE_RED_BACKUP_DIR
mkdir -p /data/shell/
cat << EOF > /data/shell/nodered_backup.sh
#!/bin/bash

NODE_RED_DIR="$NODE_RED_DIR"
NODE_RED_BACKUP_DIR="$NODE_RED_BACKUP_DIR"

mkdir -p \$NODE_RED_BACKUP_DIR
find \$NODE_RED_BACKUP_DIR/* -mtime +15 -exec rm {} \;
tar -zcf \$NODE_RED_BACKUP_DIR/nodered-backup-\$(date +"%Y%m%d%H%M%S").tar.gz -C \$NODE_RED_BACKUP_DIR \$NODE_RED_DIR

EOF
chmod +x /data/shell/nodered_backup.sh

# 添加crontab计划任务
set +e
(crontab -l 2>/dev/null; echo "0 3 * * * /data/shell/nodered_backup.sh &>> /tmp/crontab.log") | crontab -
crontab -l

# 重启crond服务
if [ "$DISTRO" == "redhat" ]; then
    systemctl restart crond
elif [ "$DISTRO" == "ubuntu" ]; then
    systemctl restart cron
fi