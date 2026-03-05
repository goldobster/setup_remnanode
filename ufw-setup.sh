#!/bin/bash

# Usage:
#   ./setup-ufw.sh [OPTIONS]
#
# Options:
#   --ip IP:PORT    Allow IP to specific port (can be repeated)
#   --port PORT     Allow additional port for everyone (can be repeated)
#   --help          Show this help message
#
# Examples:
#   ./setup-ufw.sh --ip 144.124.226.232:2222 --ip 10.0.0.1:3306 --port 80 --port 8080

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Configures UFW firewall. Ports 22 and 443 are always open.

Options:
  --ip IP:PORT    Allow IP to specific port (can be repeated)
  --port PORT     Allow additional port for everyone (can be repeated)
  --help          Show this help message

Examples:
  $0 --ip 144.124.226.232:2222 --ip 10.0.0.1:3306 --port 80 --port 8080
EOF
  exit 0
}

IP_RULES=()
EXTRA_PORTS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --ip)
      IP_RULES+=("$2")
      shift 2
      ;;
    --port)
      EXTRA_PORTS+=("$2")
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      echo "Try '$0 --help' for more information."
      exit 1
      ;;
  esac
done

sudo ufw --force reset

sudo ufw default deny incoming
sudo ufw default allow outgoing

# Always open
sudo ufw allow 22
sudo ufw allow 443

# Additional open ports
for port in "${EXTRA_PORTS[@]}"; do
  sudo ufw allow "$port"
done

# IP-specific rules
for rule in "${IP_RULES[@]}"; do
  ip="${rule%%:*}"
  port="${rule##*:}"
  sudo ufw allow from "$ip" to any port "$port"
done

sudo ufw --force enable
sudo ufw status verbose