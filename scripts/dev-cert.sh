#!/bin/zsh
# One-time: create a stable local code-signing identity so Keychain stops prompting after every rebuild.
set -e
T=$(mktemp -d); cd "$T"
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=Todoist Floating Dev" -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature"
openssl pkcs12 -export -legacy -out id.p12 -inkey key.pem -in cert.pem -passout pass:tf 2>/dev/null \
  || openssl pkcs12 -export -out id.p12 -inkey key.pem -in cert.pem -passout pass:tf
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P tf -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
rm -rf "$T"
security find-identity -v -p codesigning
