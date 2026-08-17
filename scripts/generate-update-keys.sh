#!/bin/bash
# Generates the Ed25519 key pair used to sign release archives.
#
# This is OPTIONAL hardening. Without it, the in-app updater still verifies every
# download against the SHA-256 published in the release's checksums.txt. Adding a
# key means an attacker who can serve a modified archive *and* a matching
# checksums.txt still cannot produce a valid signature.
#
#   scripts/generate-update-keys.sh
#
# Then:
#   1. Paste the public key into Resources/App-Info.plist → UpdatePublicKey.
#   2. Add the private key to the repo's GitHub Actions secrets as
#      UPDATE_SIGNING_KEY. Never commit it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/keygen.swift" <<'SWIFT'
import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
print("PRIVATE:" + key.rawRepresentation.base64EncodedString())
print("PUBLIC:" + key.publicKey.rawRepresentation.base64EncodedString())
SWIFT

swiftc -O -o "$WORK/keygen" "$WORK/keygen.swift"
OUTPUT="$("$WORK/keygen")"

PRIVATE="${OUTPUT#*PRIVATE:}"; PRIVATE="${PRIVATE%%$'\n'*}"
PUBLIC="${OUTPUT##*PUBLIC:}"

cat <<INFO

  mySolat update signing keys
  ───────────────────────────────────────────────────────────────────

  PUBLIC KEY  → paste into Resources/App-Info.plist (UpdatePublicKey)

    $PUBLIC

  PRIVATE KEY → add as GitHub Actions secret UPDATE_SIGNING_KEY
                (Settings › Secrets and variables › Actions)

    $PRIVATE

  ⚠  Store the private key in a password manager as well. If you lose it,
     existing installs can no longer verify signed updates and users will
     have to reinstall manually.

  ⚠  Never commit the private key.

INFO

# Offer to write the public key straight into the plist.
PLIST="$ROOT/Resources/App-Info.plist"
if [ -t 0 ] && [ -f "$PLIST" ]; then
  read -r -p "  Write the public key into App-Info.plist now? [y/N] " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    /usr/libexec/PlistBuddy -c "Set :UpdatePublicKey $PUBLIC" "$PLIST"
    echo "  ✓ updated $PLIST"
  fi
fi
