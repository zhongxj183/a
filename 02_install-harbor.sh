# !/bin/bash
# 离线安装harbor仓库(v2.7.1) -- 20240731

set -e

export ip='192.168.176.5'
export domain='harbor.local'

# 添加hosts
echo "$ip $domain" >> /etc/hosts

# 下载解压
#wget https://github.com/goharbor/harbor/releases/download/v2.7.1/harbor-offline-installer-v2.7.1.tgz
mkdir -p /data/harbor
tar -zxf harbor-offline-installer-v2.7.1.tgz -C /data/harbor/

# 生成证书文件
mkdir -p /data/harbor/cert/
cd /data/harbor/cert/

openssl genrsa -out ca.key 4096

openssl req -x509 -new -nodes -sha512 -days 3650 \
 -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=MyPersonal Root CA" \
 -key ca.key \
 -out ca.crt

openssl genrsa -out $domain.key 4096

openssl req -sha512 -new \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=example/OU=Personal/CN=$domain" \
    -key $domain.key \
    -out $domain.csr

cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1=$domain
EOF

openssl x509 -req -sha512 -days 3650 \
    -extfile v3.ext \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -in $domain.csr \
    -out $domain.crt

# 添加证书到docker客户端
mkdir -p /etc/docker/certs.d/$domain/
openssl x509 -inform PEM -in $domain.crt -out $domain.cert
cp $domain.cert /etc/docker/certs.d/$domain/
cp $domain.key /etc/docker/certs.d/$domain/
cp ca.crt /etc/docker/certs.d/$domain/

# 重启docker服务
systemctl restart docker

# 修改harbor配置文件
cd /data/harbor/harbor
cp harbor.yml.tmpl harbor.yml
sed -i "s/hostname: reg.mydomain.com/hostname: $domain/g" harbor.yml
sed -i "s#/your/certificate/path#/data/harbor/cert/$domain.crt#" harbor.yml
sed -i "s#/your/private/key/path#/data/harbor/cert/$domain.key#" harbor.yml
sed -i "s#data_volume: /data#data_volume: /data/harbor#" harbor.yml
sed -i "s/absolute_url: disabled/absolute_url: enabled/" harbor.yml

# 开始安装
./install.sh --with-chartmuseum

# 添加服务
cat << EOF >/etc/systemd/system/harbor.service
[Unit]
Description=Harbor
After=docker.service systemd-networkd.service systemd-resolved.service
Requires=docker.service
Documentation=http://github.com/vmware/harbor

[Service]
Type=simple
Restart=on-failure
RestartSec=5
ExecStart=/usr/bin/docker compose -f /data/harbor/harbor/docker-compose.yml up
ExecStop=/usr/bin/docker compose -f /data/harbor/harbor/docker-compose.yml down

[Install]
WantedBy=multi-user.target
EOF

# 添加权限
chmod +x /etc/systemd/system/harbor.service

# 开机自启
systemctl enable harbor.service
systemctl restart harbor.service

# 登录测试
sleep 10s
docker login -u admin -p Harbor12345 $domain
