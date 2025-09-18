#!/bin/bash
# 安装 Docker 并配置 Docker 守护进程 -- 20240813

# 下载并安装 Docker
echo "Downloading and installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh || { echo "Failed to install Docker."; exit 1; }

# 配置 Docker 守护进程
echo "Configuring Docker daemon..."
cat << EOF > /etc/docker/daemon.json
{
  "data-root": "/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "5m",
    "max-file":"1"
  },
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

# 重启 Docker 服务以应用配置
echo "Restarting Docker service to apply configuration..."
systemctl restart docker || { echo "Failed to restart Docker service."; exit 1; }

echo "Docker installation and configuration completed successfully."