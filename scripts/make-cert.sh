#!/bin/zsh
# Creates the self-signed code signing identity that keeps the Accessibility grant stable
# across rebuilds. Idempotent. Run once per Mac. macOS asks for confirmation when the
# certificate is trusted for code signing.
#
# GUSTAVE_KEYCHAIN selects another keychain. GUSTAVE_SKIP_TRUST=1 leaves trust unset.
set -euo pipefail

name="Gustave Local Signing"
keychain="${GUSTAVE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
    print "make-cert: '$name' already exists, nothing to do"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
umask 077

cat > "$work/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
    -config "$work/cert.conf" -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null

# The PKCS#12 file and its password exist only to carry the key into the keychain.
password=$(/usr/bin/openssl rand -hex 32)
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
    -name "$name" -out "$work/identity.p12" -passout "pass:$password"

# Only codesign may use the private key without asking, and the key can never be exported
# from the keychain. Any process running as you can still ask codesign to sign with it: see
# SECURITY.md for locking or deleting the key on a machine that does not build Gustave.
security import "$work/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign -x

if [[ -z "${GUSTAVE_SKIP_TRUST:-}" ]]; then
    security add-trusted-cert -p codeSign -k "$keychain" "$work/cert.pem"
fi

print "make-cert: created '$name'"
