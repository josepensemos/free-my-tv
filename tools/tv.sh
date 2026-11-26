#!/bin/bash
# Drive the rooted lab TV (LG 55UK6100PLB) from the Mac: tools/tv.sh on|off|open|status
#   on      wake it (Wake-on-LAN if it is off), screen on, wait until SSH answers
#   off     screen off; the TV stays in standby (network alive), so `on` works later
#   open    `on` + launch Free My TV (io.freemytv)
#   status  reachable / screen state
# Configuration comes from the environment, nothing is stored in the repo:
#   TV_IP            the TV's wired (Ethernet) IP; the Wi-Fi interface has another IP and MAC
#   TV_MAC           the same interface's MAC, for Wake-on-LAN
#   TV_SSH_PASSWORD  root password of the rooted TV's SSH server
#   TV_APP           optional, app to open (default io.freemytv)
# Needs: sshpass (brew install sshpass), python3.
set -u
: "${TV_IP:?Define TV_IP (Ethernet IP of the TV)}"
: "${TV_MAC:?Define TV_MAC (Ethernet MAC of the TV)}"
: "${TV_SSH_PASSWORD:?Define TV_SSH_PASSWORD}"
IP=$TV_IP
MAC=$TV_MAC
APP=${TV_APP:-io.freemytv}
PW=$TV_SSH_PASSWORD

tv() {  # run a command on the TV; -tt because luna-send fails silently without a tty
  sshpass -p "$PW" ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa -o LogLevel=ERROR \
    -o ConnectTimeout=8 -o NumberOfPasswordPrompts=1 "root@$IP" "$@" 2>&1 | tr -d '\r'
}
up() { nc -z -G 2 "$IP" 22 2>/dev/null; }
wol() {
  python3 -I - "$MAC" "${IP%.*}.255" <<'PY'
import socket, sys
mac = bytes.fromhex(sys.argv[1].replace(':', ''))
packet = b'\xff' * 6 + mac * 16
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
for port in (9, 7):
    s.sendto(packet, (sys.argv[2], port))
PY
}
wait_ssh() {  # $1 = seconds
  for _ in $(seq 1 "$1"); do up && return 0; sleep 1; done
  return 1
}
power() {  # $1 = turnOnScreen | turnOffScreen
  tv "luna-send -n 1 -w 4000 luna://com.webos.service.tvpower/power/$1 '{\"standbyMode\":\"active\"}'"
}
on() {
  if ! up; then
    for _ in 1 2 3 4 5 6; do wol; wait_ssh 10 && break; done
  fi
  up || { echo "La TV no responde en $IP tras Wake-on-LAN." >&2; exit 1; }
  sleep 3   # the sshd answers before the TV has finished resuming
  power turnOnScreen | grep -v -e '"-102"' || true   # -102: the screen was already on
}

case "${1:-}" in
  on)     on ;;
  off)    up || { echo "La TV ya no responde (apagada del todo)."; exit 0; }; power turnOffScreen ;;
  open)   on && sleep 2 && tv "luna-send-pub -n 1 -f luna://com.webos.applicationManager/launch '{\"id\":\"$APP\"}'" ;;
  status) if up; then echo "TV alcanzable en $IP"; else ping -c1 -t2 "$IP" >/dev/null 2>&1 && echo "Responde a ping, SSH cerrado" || echo "TV inalcanzable (apagada del todo o IP distinta)"; fi ;;
  *)      echo "Uso: $0 on|off|open|status" >&2; exit 2 ;;
esac
