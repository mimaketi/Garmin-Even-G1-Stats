#!/usr/bin/env bash
# Build the G1 PoC for all devices listed in manifest.xml.
# Needs: Connect IQ SDK on PATH, device files downloaded via SDK Manager
# (login once), and a developer key (developer_key.der).
#   monkeyc not found? export PATH="$HOME/.Garmin/ConnectIQ/Sdks/<sdk>/bin:$PATH"
#   make a key:  openssl genrsa -out developer_key.pem 4096 && \
#     openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem \
#       -out developer_key.der -nocrypt
set -euo pipefail

KEY="${1:-developer_key.der}"
MANIFEST="${2:-manifest.xml}"
FAILED=()

mkdir -p bin

# Parse device IDs directly from the manifest
DEVICES=$(grep -oP '(?<=<iq:product id=")[^"]+' "$MANIFEST")

for DEVICE in $DEVICES; do
    OUT="bin/G1Poc-${DEVICE}.prg"
    echo "Building $DEVICE..."
    if monkeyc -f monkey.jungle -d "$DEVICE" -o "$OUT" -y "$KEY" -w -l 2; then
        echo "  OK -> $OUT"
    else
        echo "  FAILED: $DEVICE"
        FAILED+=("$DEVICE")
    fi
done

echo ""
echo "Build complete. $(( $(echo "$DEVICES" | wc -w) - ${#FAILED[@]} )) succeeded, ${#FAILED[@]} failed."

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Failed devices:"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi

echo ""
echo "Simulator:  connectiq &   then   monkeydo bin/G1Poc-<device>.prg <device>"
