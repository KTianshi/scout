#!/bin/bash
# One-time: create a self-signed code-signing identity "Scout Dev" in your login keychain,
# so rebuilt copies of Scout keep their Screen Recording / Accessibility / Microphone permissions.
# Run this yourself (it adds a certificate to your keychain; macOS may ask for your password).
set -euo pipefail
NAME="Scout Dev"
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then echo "'$NAME' already exists."; exit 0; fi
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/cfg" <<CFG
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$T/cfg" -keyout "$T/key.pem" -out "$T/cert.pem" >/dev/null 2>&1
PASS="scout-$RANDOM$RANDOM"
openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -name "$NAME" -out "$T/id.p12" -passout "pass:$PASS" -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -name "$NAME" -out "$T/id.p12" -passout "pass:$PASS"
security import "$T/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign
# Trust it for code signing (asks for your password).
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db "$T/cert.pem"
security find-identity -v -p codesigning | grep "$NAME" && echo "Done. Re-run scripts/bundle.sh."
