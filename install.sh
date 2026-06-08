#!/bin/bash

# Выходим при любой ошибке
set -e

echo "========================================================="
echo "=== 1. Настройка и активация TCP BBR ==="
echo "========================================================="

if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "BBR уже активирован на этом сервере."
else
    echo "Включаем BBR..."
    sudo sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sudo sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
fi

echo -n "Текущий алгоритм контроля конгестии: "
sysctl net.ipv4.tcp_congestion_control

echo "========================================================="
echo "=== 2. Подготовка окружения для CrowdSec ==="
echo "========================================================="
sudo apt-get update
sudo apt-get install wget tar iptables -y

echo "========================================================="
echo "=== 3. Скачивание и установка движка CrowdSec ==="
echo "========================================================="
cd /tmp
wget https://github.com/crowdsecurity/crowdsec/releases/download/v1.6.2/crowdsec-release.tgz
tar xzvf crowdsec-release.tgz
cd crowdsec-v1.6.2/
sudo ./wizard.sh --accept-defaults

# Создаем systemd-сервис для движка CrowdSec, если wizard.sh его не создал
echo "Создание systemd-сервиса для crowdsec..."
cat <<EOF | sudo tee /etc/systemd/system/crowdsec.service
[Unit]
Description=CrowdSec lightweight devops security engine
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/crowdsec
ExecStartPre=/usr/local/bin/crowdsec -t
ExecStart=/usr/local/bin/crowdsec -c /etc/crowdsec/config.yaml
ExecReload=/bin/kill -HUP \$MAINPID
TimeoutStopSec=60
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "========================================================="
echo "=== 4. Скачивание и установка Firewall Bouncer ==="
echo "========================================================="
cd /tmp
wget https://github.com/crowdsecurity/cs-firewall-bouncer/releases/download/v0.0.30/crowdsec-firewall-bouncer.tgz
tar xzvf crowdsec-firewall-bouncer.tgz
cd crowdsec-firewall-bouncer-v0.0.30/
sudo ./install.sh

# На всякий случай создаем systemd-сервис для Баунсера
echo "Создание systemd-сервиса для crowdsec-firewall-bouncer..."
cat <<EOF | sudo tee /etc/systemd/system/crowdsec-firewall-bouncer.service
[Unit]
Description=The firewall bouncer for CrowdSec
After=crowdsec.service

[Service]
Type=simple
ExecStart=/usr/local/bin/crowdsec-firewall-bouncer -c /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

echo "========================================================="
echo "=== 5. Принудительная настройка режима iptables ==="
echo "========================================================="
CONFIG_FILE="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml"
if [ -f "$CONFIG_FILE" ]; then
    sudo sed -i 's/^mode:.*/mode: iptables/' "$CONFIG_FILE"
else
    echo "Ошибка: Конфигурационный файл баунсера не найден!"
    exit 1
fi

echo "========================================================="
echo "=== 6. Перезапуск и проверка служб ==="
echo "========================================================="
sudo systemctl daemon-reload

sudo systemctl enable crowdsec
sudo systemctl enable crowdsec-firewall-bouncer

sudo systemctl restart crowdsec
sudo systemctl restart crowdsec-firewall-bouncer

echo "========================================================="
echo "=== ВСЁ ГОТОВО! ==="
echo "========================================================="
echo "Статус BBR: \$(sysctl net.ipv4.tcp_congestion_control)"
echo "Статус CrowdSec движка: \$(sudo systemctl is-active crowdsec)"
echo "Статус баунсера файрвола: \$(sudo systemctl is-active crowdsec-firewall-bouncer)"
echo "--------------------------------------------------------─"
sudo cscli bouncers list
