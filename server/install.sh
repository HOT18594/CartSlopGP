#!/bin/bash
# Runs once on first boot from cloud-init. Installs dependencies and starts
# the Cart Slop GP server on every boot.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[cartslop] installing packages"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if apt-get update -y && apt-get install -y python3 avahi-daemon miniupnpc iw openssh-server; then
    break
  fi
  echo "[cartslop] apt attempt $attempt failed, retrying"
  sleep 8
done

install -d -m 755 /opt/cartslop
if [ "$DIR" != "/opt/cartslop" ]; then
  cp -a "$DIR"/. /opt/cartslop/
fi
chmod +x /opt/cartslop/cartslop_server.py /opt/cartslop/install.sh

cat > /etc/systemd/system/cartslop-server.service <<'UNIT'
[Unit]
Description=Cart Slop GP lobby and UDP relay
After=network-online.target NetworkManager-wait-online.service
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/cartslop
ExecStart=/usr/bin/python3 /opt/cartslop/cartslop_server.py
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/wifi-powersave-off.service <<'UNIT'
[Unit]
Description=Disable Wi-Fi power saving for stable game latency
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'iw dev wlan0 set power_save off || true'

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now cartslop-server.service
systemctl enable --now avahi-daemon.service
systemctl enable wifi-powersave-off.service

echo "[cartslop] server installed; console on http://cartslop.local:42777"
