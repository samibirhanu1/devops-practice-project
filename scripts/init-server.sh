#!/bin/bash
# Prepare a fresh Ubuntu server. Safe to run more than once.
set -eo pipefail
export DEBIAN_FRONTEND=noninteractive

# Set to your public key if you want the script to install it for deployer.
# Terraform will fill this in later.
DEPLOYER_PUBLIC_KEY=""

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root (sudo bash init-server.sh)" >&2
  exit 1
fi

echo "==> 1. System update and packages"
apt-get update
if [ "$LAB_MODE" = "1" ]; then
  apt-get install -y curl git sudo cron ufw
else
  apt-get install -y curl git sudo cron ufw docker.io docker-compose-v2
  systemctl enable --now docker
fi

echo "==> 2. deployer user"
id deployer >/dev/null 2>&1 || useradd -m -s /bin/bash deployer
getent group docker >/dev/null || groupadd docker
usermod -aG docker deployer

echo "deployer ALL=(ALL) NOPASSWD: /usr/bin/docker" > /etc/sudoers.d/deployer
chmod 440 /etc/sudoers.d/deployer
visudo -cf /etc/sudoers.d/deployer

install -d -o deployer -g deployer /home/deployer/app

if [ -n "$DEPLOYER_PUBLIC_KEY" ]; then
  install -d -m 700 -o deployer -g deployer /home/deployer/.ssh
  touch /home/deployer/.ssh/authorized_keys
  grep -qxF "$DEPLOYER_PUBLIC_KEY" /home/deployer/.ssh/authorized_keys \
    || echo "$DEPLOYER_PUBLIC_KEY" >> /home/deployer/.ssh/authorized_keys
  chmod 600 /home/deployer/.ssh/authorized_keys
  chown deployer:deployer /home/deployer/.ssh/authorized_keys
fi

echo "==> 3. Firewall"
if [ "$LAB_MODE" = "1" ]; then
  echo "LAB_MODE: skipping ufw (needs a real server)"
else
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
fi

echo "==> 4. Log cleanup job"
mkdir -p /var/log/app

cat > /usr/local/bin/clean-logs.sh <<'EOF'
#!/bin/bash
# Delete .log files in /var/log/app that are older than 7 days.
set -e

LOG_DIR=/var/log/app

[ -d "$LOG_DIR" ] || exit 0

find "$LOG_DIR" -type f -name "*.log" -mtime +7 -print -delete
EOF
chmod +x /usr/local/bin/clean-logs.sh

echo "0 0 * * * root /usr/local/bin/clean-logs.sh >> /var/log/clean-logs.cron.log 2>&1" > /etc/cron.d/clean-logs
chmod 644 /etc/cron.d/clean-logs

echo "==> Done"