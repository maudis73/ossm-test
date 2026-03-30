#!/usr/bin/env bash
# Generate mesh PKI (Red Hat § 6.2.1 style) into PKI_DIR. See docs/ossm-multi-cluster-mesh-provisioning.md §3.
set -euo pipefail

PKI_DIR="${PKI_DIR:?Set PKI_DIR to output directory (e.g. ~/ossm-mesh-certs)}"
mkdir -p "$PKI_DIR"
cd "$PKI_DIR"

if [[ -f east/ca-cert.pem && -f west/ca-cert.pem && "${FORCE_PKI:-0}" != "1" ]]; then
  echo "PKI already present under $PKI_DIR (set FORCE_PKI=1 to regenerate)."
  exit 0
fi

echo "Generating PKI in $PKI_DIR ..."

cat >root-ca.conf <<'EOF'
encrypt_key = no
prompt = no
utf8 = yes
default_md = sha256
default_bits = 4096
req_extensions = req_ext
x509_extensions = req_ext
distinguished_name = req_dn
[ req_ext ]
subjectKeyIdentifier = hash
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, keyCertSign
[ req_dn ]
O = Istio
CN = Root CA
EOF

openssl genrsa -out root-key.pem 4096
openssl req -sha256 -new -key root-key.pem -config root-ca.conf -out root-cert.csr
openssl x509 -req -sha256 -days 3650 \
  -signkey root-key.pem -extensions req_ext -extfile root-ca.conf \
  -in root-cert.csr -out root-cert.pem

for loc in east west; do
  mkdir -p "$loc"
  openssl genrsa -out "$loc/ca-key.pem" 4096
done

cat >east/intermediate.conf <<'EOF'
[ req ]
encrypt_key = no
prompt = no
utf8 = yes
default_md = sha256
default_bits = 4096
req_extensions = req_ext
x509_extensions = req_ext
distinguished_name = req_dn
[ req_ext ]
subjectKeyIdentifier = hash
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, keyCertSign
subjectAltName=@san
[ san ]
DNS.1 = istiod.istio-system.svc
[ req_dn ]
O = Istio
CN = Intermediate CA
L = east
EOF

cat >west/intermediate.conf <<'EOF'
[ req ]
encrypt_key = no
prompt = no
utf8 = yes
default_md = sha256
default_bits = 4096
req_extensions = req_ext
x509_extensions = req_ext
distinguished_name = req_dn
[ req_ext ]
subjectKeyIdentifier = hash
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, nonRepudiation, keyEncipherment, keyCertSign
subjectAltName=@san
[ san ]
DNS.1 = istiod.istio-system.svc
[ req_dn ]
O = Istio
CN = Intermediate CA
L = west
EOF

for loc in east west; do
  openssl req -new -config "$loc/intermediate.conf" -key "$loc/ca-key.pem" -out "$loc/cluster-ca.csr"
  openssl x509 -req -sha256 -days 3650 \
    -CA root-cert.pem -CAkey root-key.pem -CAcreateserial \
    -extensions req_ext -extfile "$loc/intermediate.conf" \
    -in "$loc/cluster-ca.csr" -out "$loc/ca-cert.pem"
  cat "$loc/ca-cert.pem" root-cert.pem >"$loc/cert-chain.pem"
  cp root-cert.pem "$loc/"
done

echo "Done. Verify:"
for d in east west; do
  ls -l "$d/ca-cert.pem" "$d/ca-key.pem" "$d/root-cert.pem" "$d/cert-chain.pem"
done
