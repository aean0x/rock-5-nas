#!/usr/bin/env bash
# Start PXE server for netboot (build first with ./deploy build-netboot)
# Chain: dnsmasq(DHCP+TFTP) -> snp.efi(iPXE) -> HTTP(kernel+initrd)
set -euo pipefail
source "$(dirname "$0")/common.sh"
cd "${REPO_ROOT}"

# Build if result doesn't exist or isn't a netboot output
if [[ ! -d result ]] || [[ ! -f result/snp.efi ]]; then
    info "No netboot build found, building now..."
    "${REPO_ROOT}/scripts/build-netboot.sh"
fi

NETBOOT_DIR="$(readlink -f result)"
info "Netboot images: ${NETBOOT_DIR}"

HTTP_PORT=8880

# ===================
# Network mode selection
# ===================
echo ""
echo "Network mode:"
echo "  1) LAN — workstation and device on the same network (DHCP proxy mode)"
echo "  2) Direct — ethernet cable between workstation and device (full DHCP)"
echo ""
read -p "Select mode [1/2]: " NET_MODE

DIRECT_SUBNET="192.168.100"

if [[ "$NET_MODE" == "2" ]]; then
    # --- Direct connect mode ---
    info "Direct connect mode"
    echo ""

    # List available ethernet interfaces (exclude loopback, wifi, docker, virtual)
    echo "Available ethernet interfaces:"
    ETHS=()
    while IFS= read -r line; do
        iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
        state=$(echo "$line" | grep -oP 'state \K\S+')
        # Show all physical ethernet interfaces
        if [[ "$iface" != lo ]] && [[ "$iface" != docker* ]] && [[ "$iface" != veth* ]] && [[ "$iface" != br-* ]] && [[ "$iface" != wl* ]]; then
            ETHS+=("$iface")
            echo "  ${#ETHS[@]}) ${iface} (${state:-unknown})"
        fi
    done < <(ip -o link show 2>/dev/null)

    if [[ ${#ETHS[@]} -eq 0 ]]; then
        error "No ethernet interfaces found."
        exit 1
    fi

    if [[ ${#ETHS[@]} -eq 1 ]]; then
        IFACE="${ETHS[0]}"
        info "Using ${IFACE}"
    else
        read -p "Select interface [1-${#ETHS[@]}]: " ETH_IDX
        IFACE="${ETHS[$((ETH_IDX - 1))]}"
    fi

    SERVER_IP="${DIRECT_SUBNET}.1"
    DEVICE_RANGE_START="${DIRECT_SUBNET}.10"
    DEVICE_RANGE_END="${DIRECT_SUBNET}.50"

    echo ""
    info "Setting up ${IFACE} with ${SERVER_IP}/24..."
    sudo ip addr flush dev "${IFACE}" 2>/dev/null || true
    sudo ip addr add "${SERVER_IP}/24" dev "${IFACE}"
    sudo ip link set "${IFACE}" up

    # Wait for link
    info "Waiting for link on ${IFACE}..."
    for i in $(seq 1 15); do
        STATE=$(cat "/sys/class/net/${IFACE}/carrier" 2>/dev/null || echo "0")
        [[ "$STATE" == "1" ]] && break
        echo -n "."
        sleep 1
    done
    echo ""

    STATE=$(cat "/sys/class/net/${IFACE}/carrier" 2>/dev/null || echo "0")
    if [[ "$STATE" != "1" ]]; then
        warn "No link detected on ${IFACE}. Is the cable plugged in?"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo ""
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    else
        info "Link up on ${IFACE}"
    fi

    DHCP_MODE="full"
else
    # --- LAN proxy mode ---
    SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' || true)
    if [[ -z "$SERVER_IP" ]]; then
        read -p "Could not detect LAN IP. Enter your workstation IP: " SERVER_IP
    else
        echo "Detected workstation IP: ${SERVER_IP}"
        read -p "Use this IP? [Y/n] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            read -p "Enter workstation IP: " SERVER_IP
        fi
    fi

    IFACE=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' || true)
    DHCP_MODE="proxy"
fi

# ===================
# Set up serving directories
# ===================
TFTP_DIR=$(mktemp -d)
HTTP_DIR=$(mktemp -d)

cleanup() {
    info "Cleaning up..."
    # Remove firewall rules
    sudo iptables -D nixos-fw -p udp --dport 67 -j nixos-fw-accept 2>/dev/null || true
    sudo iptables -D nixos-fw -p udp --dport 69 -j nixos-fw-accept 2>/dev/null || true
    sudo iptables -D nixos-fw -p udp --dport 4011 -j nixos-fw-accept 2>/dev/null || true
    sudo iptables -D nixos-fw -p tcp --dport ${HTTP_PORT} -j nixos-fw-accept 2>/dev/null || true
    rm -rf "${TFTP_DIR}" "${HTTP_DIR}"
    kill 0 2>/dev/null || true
}
trap cleanup EXIT

# Open firewall ports (insert before nixos-fw-log-refuse)
info "Opening firewall ports (67/udp, 69/udp, 4011/udp, ${HTTP_PORT}/tcp)..."
sudo iptables -I nixos-fw -p udp --dport 67 -j nixos-fw-accept
sudo iptables -I nixos-fw -p udp --dport 69 -j nixos-fw-accept
sudo iptables -I nixos-fw -p udp --dport 4011 -j nixos-fw-accept
sudo iptables -I nixos-fw -p tcp --dport ${HTTP_PORT} -j nixos-fw-accept

# TFTP: iPXE firmware + boot script (small files)
cp "${NETBOOT_DIR}/snp.efi" "${TFTP_DIR}/snp.efi"

# HTTP: kernel + initrd (large files, HTTP is much faster than TFTP)
cp "${NETBOOT_DIR}/Image" "${HTTP_DIR}/Image"
cp "${NETBOOT_DIR}/initrd" "${HTTP_DIR}/initrd"

# Read init= path from NixOS-generated iPXE script
INIT_PARAM=$(grep -oP 'init=\S+' "${NETBOOT_DIR}/netboot.ipxe" || true)

# Generate iPXE boot script — fetches kernel+initrd over HTTP
cat > "${TFTP_DIR}/boot.ipxe" << IPXE_EOF
#!ipxe
kernel http://${SERVER_IP}:${HTTP_PORT}/Image ${INIT_PARAM} initrd=initrd rootwait earlycon consoleblank=0 console=tty1 console=ttyS2,115200n8 loglevel=4
initrd http://${SERVER_IP}:${HTTP_PORT}/initrd
boot
IPXE_EOF

# ===================
# Start servers
# ===================
info "Starting netboot server on ${SERVER_IP} (${DHCP_MODE} mode, interface ${IFACE})..."
echo ""
echo "TFTP: ${TFTP_DIR}  (snp.efi + boot.ipxe)"
echo "HTTP: ${HTTP_DIR}  (kernel + initrd on port ${HTTP_PORT})"
echo ""
echo "Boot chain:"
echo "  1. EDK2 PXE -> dnsmasq DHCP -> TFTP snp.efi (319K)"
echo "  2. iPXE snp.efi -> dnsmasq detects iPXE -> TFTP boot.ipxe"
echo "  3. boot.ipxe -> HTTP kernel (~40MB) + initrd (~439MB)"
echo "  4. Linux boots with embedded squashfs NixOS root"
echo ""
echo "On the Rock 5 ITX:"
echo "  1. Power on, press Escape for EDK2 menu"
echo "  2. Boot Manager > UEFI PXE IPv4"
echo ""
if [[ "$DHCP_MODE" == "full" ]]; then
    echo "After boot:"
    echo "  1. Ctrl+C to stop PXE server"
    echo "  2. Plug device into your router (needs WAN for nixos-install)"
    echo "  3. ./deploy install"
else
    echo "After boot:  ./deploy install"
fi
echo ""
warn "Press Ctrl+C to stop the netboot server."
echo ""

# Start HTTP server in background
python3 -m http.server ${HTTP_PORT} --directory "${HTTP_DIR}" --bind "${SERVER_IP}" &
HTTP_PID=$!
info "HTTP server started (PID ${HTTP_PID}, port ${HTTP_PORT})"

# Build dnsmasq arguments
DNSMASQ_ARGS=(
    --no-daemon
    --port=0
    --dhcp-match=set:aarch64-efi,option:client-arch,11
    --dhcp-match=set:ipxe,175
    --dhcp-boot=tag:!ipxe,tag:aarch64-efi,snp.efi
    --dhcp-boot=tag:ipxe,boot.ipxe
    --enable-tftp
    --tftp-root="${TFTP_DIR}"
    --log-dhcp
    --log-queries
    --log-facility=-
)

if [[ -n "${IFACE}" ]]; then
    DNSMASQ_ARGS+=(--interface="${IFACE}")
    DNSMASQ_ARGS+=(--except-interface=lo)
fi

if [[ "$DHCP_MODE" == "proxy" ]]; then
    DNSMASQ_ARGS+=(--dhcp-range="${SERVER_IP},proxy")
else
    # Full DHCP server for direct connect — hands out IPs on the direct link
    DNSMASQ_ARGS+=(
        --dhcp-range="${DEVICE_RANGE_START},${DEVICE_RANGE_END},255.255.255.0,1h"
        --dhcp-option=option:router,${SERVER_IP}
        --dhcp-option=option:dns-server,1.1.1.1
        --dhcp-option=66,${SERVER_IP}
    )
fi

sudo "$(which dnsmasq)" "${DNSMASQ_ARGS[@]}"
