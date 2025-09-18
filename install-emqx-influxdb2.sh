# 禁用交换分区
swapoff -a
sed -i '/swap.img/s/^/#/' /etc/fstab

# ulimit:用户最大句柄数
ulimit -n 1048576


cat << EOF >> /etc/systemd/system.conf
# 设置服务最大文件句柄数
DefaultLimitNOFILE=1048576
EOF

cat << EOF >> /etc/security/limits.conf
# 允许用户/进程打开文件句柄数
* soft nofile 1048576 
* hard nofile 1048576
EOF

cat << EOF >> /etc/sysctl.conf
# 系统全局允许分配的最大文件句柄数
fs.file-max = 1048576
fs.nr_open = 2097152
# 并发连接 backlog 设置
net.core.somaxconn = 32768 
net.ipv4.tcp_max_syn_backlog = 16384 
net.core.netdev_max_backlog = 16384
# 可用知名端口范围
net.ipv4.ip_local_port_range = 1024  65535
# TCP Socket读写Buffer设置
net.core.wmem_default = 262144
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.optmem_max = 16777216
#net.ipv4.tcp_mem = 16777216 16777216 16777216
net.ipv4.tcp_rmem = 1024 4096 16777216
net.ipv4.tcp_wmem = 1024 4096 16777216
# TCP 连接追踪设置
net.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_max = 1000000
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
# TIME-WAIT Socket 最大数量
net.ipv4.tcp_max_tw_buckets = 1048576
# FIN-WAIT-2 Socket 超时设置
sysctl -w net.ipv4.tcp_fin_timeout = 15
EOF



curl -s https://assets.emqx.com/scripts/install-emqx-deb.sh | sudo bash
apt install -y emqx
systemctl enable emqx --now
systemctl status emqx



# 安装influxdb2
curl -LO https://download.influxdata.com/influxdb/releases/influxdb2_2.7.12-1_amd64.deb
sudo dpkg -i influxdb2_2.7.12-1_amd64.deb
sudo useradd influxdb
sudo mkdir -p /data/influxdb
sudo chown influxdb:influxdb /data/influxdb

sudo su
cat > /etc/influxdb/config.toml <<EOF
bolt-path = "/data/influxdb/influxd.bolt"
engine-path = "/data/influxdb/engine"
query-log-enabled = "true"
reporting-disabled = "true"
http-read-timeout = "20s"
http-write-timeout = "20s"
EOF
exit

sudo systemctl start influxd
sudo systemctl status influxd