#!/usr/bin/env zsh

set -e

SSID="MYSSIDWIFI"
PASS="PASSWRODHERE"
CONF="/etc/wpa_supplicant/${SSID}.conf"
ROOTPW="ROOTPASSWORDHERE"

echo "[*] Loading Danish keyboard…"
loadkeys dk-latin1

echo "[*] Waiting for wireless interface…"
for i in {1..10}; do
    iface=$(iw dev | awk '/Interface/ {print $2}')
    if [[ -n "$iface" ]]; then
        echo "[+] Found wireless interface: $iface"
        break
    fi
    echo "[-] No interface yet, retrying ($i/10)…"
    sleep 1
done

if [[ -z "$iface" ]]; then
    echo "[!] No wireless interface detected. Exiting."
    exit 1
fi

echo "[*] Bringing interface up…"
ip link set "$iface" up || {
    echo "[!] Failed to bring interface up."
    exit 1
}

echo "[*] Scanning for networks…"
iw dev "$iface" scan >/dev/null 2>&1 || {
    echo "[!] Scan failed. Retrying in 2 seconds…"
    sleep 2
    iw dev "$iface" scan || {
        echo "[!] Scan failed again. Exiting."
        exit 1
    }
}

echo "[*] Creating wpa_supplicant config…"
wpa_passphrase "$SSID" "$PASS" > "$CONF"

echo "[*] Starting wpa_supplicant…"
wpa_supplicant -B -i "$iface" -c "$CONF" || {
    echo "[!] wpa_supplicant failed."
    exit 1
}

echo "[*] Requesting IP address via DHCP…"
dhcpcd "$iface" || {
    echo "[!] dhcpcd failed."
    exit 1
}

echo "[+] Connection established!"
echo "[*] Local IP address:"
ip -4 addr show "$iface" | awk '/inet/ {print $2}'

echo "[*] Setting root password non-interactively…"
echo "root:${ROOTPW}" | chpasswd