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
mkdir -p bin
monkeyc -f monkey.jungle -d fenix7 -o bin/G1Poc.prg -y "$KEY" -w -l 2
echo "Built bin/G1Poc.prg"
echo "Simulator:  connectiq &   then   monkeydo bin/G1Poc.prg fenix7"
