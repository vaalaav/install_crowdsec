#!/bin/bash

# Выходим при любой ошибке
set -e

echo "========================================================="
echo "=== 1. Настройка и активация TCP BBR ==="
echo "========================================================="

# Проверяем, не включен ли BBR уже в системе
if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo "BBR уже активирован на этом сервере."
else
    echo "Включаем BBR..."
    # Удаляем старые записи, если они были, чтобы избежать дублирования
    sudo sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sudo sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    
    # Записываем новые параметры для работы BBR
    echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
    
    # Применяем изменения в системе без перезагрузки
    sudo sysctl -p
fi

# Контрольная проверка включения BBR
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
# Автоматическая тихая установка со стандартными настройками
sudo ./wizard.sh --accept-defaults

echo "========================================================="
echo "=== 4. Скачивание и установка Firewall Bouncer ==="
echo "========================================================="
cd /tmp
wget https://github.com/crowdsecurity/cs-firewall-bouncer/releases/download/v0.0.30/crowdsec-firewall-bouncer.tgz
tar xzvf crowdsec-firewall-bouncer.tgz
cd crowdsec-firewall-bouncer-v0.0.30/
sudo ./install.sh

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
sudo systemctl restart crowdsec
sudo systemctl restart crowdsec-firewall-bouncer

echo "========================================================="
echo "=== ВСЁ ГОТОВО! ==="
echo "========================================================="
echo "Статус BBR: $(sysctl net.ipv4.tcp_congestion_control)"
echo "Статус CrowdSec движка: $(sudo systemctl is-active crowdsec)"
echo "Статус баунсера файрвола: $(sudo systemctl is-active crowdsec-firewall-bouncer)"
echo "--------------------------------------------------------─"
sudo cscli bouncers list
