#!/usr/bin/env bash
#
# Automates OSSM 3.3 multi-cluster "Day 1" infra (provisioning doc §1b–§9).
#
# Prerequisites:
#   - oc, openssl, python3 + PyYAML, istioctl (aligned with ISTIO_VERSION)
#   - Valid kubeconfigs (oc login); tokens expire — refresh before running.
#
# Usage:
#   export KUBECONFIG_EAST=/path/to/east-kubeconfig
#   export KUBECONFIG_WEST=/path/to/west-kubeconfig
#   export ISTIO_VERSION=1.28.5   # optional
#   ./scripts/day1-deploy.sh [--with-console] [--skip-pki]
#
set -euo pipefail

WITH_CONSOLE=0
SKIP_PKI=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-console) WITH_CONSOLE=1 ;;
    --skip-pki) SKIP_PKI=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
  shift
done

: "${KUBECONFIG_EAST:?Set KUBECONFIG_EAST to East cluster kubeconfig path}"
: "${KUBECONFIG_WEST:?Set KUBECONFIG_WEST to West cluster kubeconfig path}"

export ISTIO_VERSION="${ISTIO_VERSION:-1.28.5}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKI_DIR="${PKI_DIR:-$REPO_ROOT/ossm-mesh-certs}"
PATCHER="$REPO_ROOT/scripts/rosa-patch-remote-secret.py"
TMP="${TMPDIR:-/tmp}/ossm-day1-$$"
mkdir -p "$TMP"

oc_east() { oc --kubeconfig "$KUBECONFIG_EAST" "$@"; }
oc_west() { oc --kubeconfig "$KUBECONFIG_WEST" "$@"; }

die() { echo "ERROR: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

need_cmd oc
need_cmd openssl
need_cmd python3
need_cmd istioctl

python3 -c "import yaml" 2>/dev/null || die "python3 PyYAML required (e.g. dnf install python3-pyyaml)"

echo "== Preflight: API access"
oc_east get ns >/dev/null || die "East: oc cannot reach API (refresh login / KUBECONFIG_EAST)"
oc_west get ns >/dev/null || die "West: oc cannot reach API (refresh login / KUBECONFIG_WEST)"

apply_subscription() {
  local kc=$1
  oc --kubeconfig "$kc" apply -f - <<'EOSUB'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator3
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator3
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOSUB
}

wait_csv_servicemesh() {
  local kc=$1
  local csv phase
  echo "Waiting for Service Mesh CSV (up to ~15m) on $(basename "$kc") ..."
  for _ in $(seq 1 90); do
    while read -r csv; do
      [[ -z "$csv" ]] && continue
      phase=$(oc --kubeconfig "$kc" get csv -n openshift-operators "$csv" -o jsonpath='{.status.phase}' 2>/dev/null || true)
      if [[ "$phase" == Succeeded ]]; then
        echo "CSV ready: $csv"
        return 0
      fi
    done < <(oc --kubeconfig "$kc" get csv -n openshift-operators -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -i servicemesh || true)
    sleep 10
  done
  die "Service Mesh CSV did not reach Succeeded on $kc"
}

apply_istiocni() {
  local kc=$1
  oc --kubeconfig "$kc" get project istio-cni >/dev/null 2>&1 || oc --kubeconfig "$kc" new-project istio-cni
  oc --kubeconfig "$kc" apply -f - <<EOF
apiVersion: sailoperator.io/v1
kind: IstioCNI
metadata:
  name: default
  namespace: istio-cni
spec:
  version: v${ISTIO_VERSION}
EOF
}

wait_istiocni() {
  local kc=$1
  echo "Waiting for Istio CNI pods on $(basename "$kc") ..."
  for _ in $(seq 1 60); do
    if oc --kubeconfig "$kc" get pods -n istio-cni -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; then
      return 0
    fi
    sleep 10
  done
  die "Istio CNI pods not Running in time on $kc (oc get pods -n istio-cni; oc describe istiocni -n istio-cni)"
}

echo "== §1b Operator subscription (East + West)"
apply_subscription "$KUBECONFIG_EAST"
apply_subscription "$KUBECONFIG_WEST"
wait_csv_servicemesh "$KUBECONFIG_EAST"
wait_csv_servicemesh "$KUBECONFIG_WEST"

echo "== §1b Istio CNI (East + West)"
apply_istiocni "$KUBECONFIG_EAST"
apply_istiocni "$KUBECONFIG_WEST"
wait_istiocni "$KUBECONFIG_EAST"
wait_istiocni "$KUBECONFIG_WEST"

if [[ "$WITH_CONSOLE" == 1 ]]; then
  echo "== §1c Console notifications"
  oc_east apply -f "$REPO_ROOT/manifests/console/east-console-notification.yaml"
  oc_west apply -f "$REPO_ROOT/manifests/console/west-console-notification.yaml"
fi

echo "== §3 PKI"
if [[ "$SKIP_PKI" == 1 ]]; then
  [[ -f "$PKI_DIR/east/ca-cert.pem" ]] || die "--skip-pki but $PKI_DIR/east/ca-cert.pem missing"
else
  PKI_DIR="$PKI_DIR" bash "$REPO_ROOT/scripts/generate-mesh-pki.sh"
fi

echo "== §4 cacerts (East network1, West network2)"
oc_east get project istio-system >/dev/null 2>&1 || oc_east new-project istio-system
oc_east label namespace istio-system topology.istio.io/network=network1 --overwrite
if oc_east get secret cacerts -n istio-system >/dev/null 2>&1; then
  echo "East: replacing existing cacerts"
  oc_east delete secret cacerts -n istio-system
fi
oc_east create secret generic cacerts -n istio-system \
  --from-file="$PKI_DIR/east/ca-cert.pem" \
  --from-file="$PKI_DIR/east/ca-key.pem" \
  --from-file="$PKI_DIR/east/root-cert.pem" \
  --from-file="$PKI_DIR/east/cert-chain.pem"

oc_west get project istio-system >/dev/null 2>&1 || oc_west new-project istio-system
oc_west label namespace istio-system topology.istio.io/network=network2 --overwrite
if oc_west get secret cacerts -n istio-system >/dev/null 2>&1; then
  echo "West: replacing existing cacerts"
  oc_west delete secret cacerts -n istio-system
fi
oc_west create secret generic cacerts -n istio-system \
  --from-file="$PKI_DIR/west/ca-cert.pem" \
  --from-file="$PKI_DIR/west/ca-key.pem" \
  --from-file="$PKI_DIR/west/root-cert.pem" \
  --from-file="$PKI_DIR/west/cert-chain.pem"

echo "== §5–7 Istio CR (East cluster1, West cluster2)"
oc_east apply -f - <<EOF
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: default
spec:
  version: v${ISTIO_VERSION}
  namespace: istio-system
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster1
      network: network1
EOF
oc_west apply -f - <<EOF
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: default
spec:
  version: v${ISTIO_VERSION}
  namespace: istio-system
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster2
      network: network2
EOF

echo "Waiting for Istio Ready (up to 15m per cluster) ..."
oc_east wait --for=condition=Ready "istio/default" -n istio-system --timeout=900s
oc_west wait --for=condition=Ready "istio/default" -n istio-system --timeout=900s

echo "== §6–8 East–west gateway + cross-network Gateway (namespace istio-eastwest)"
oc_east apply -k "$REPO_ROOT/manifests/istio-eastwest/cluster1"
oc_west apply -k "$REPO_ROOT/manifests/istio-eastwest/cluster2"

echo "Waiting for istio-eastwestgateway external hostname ..."
for kc in "$KUBECONFIG_EAST" "$KUBECONFIG_WEST"; do
  for _ in $(seq 1 60); do
    h=$(oc --kubeconfig "$kc" -n istio-eastwest get svc istio-eastwestgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    [[ -n "$h" ]] && break
    ip=$(oc --kubeconfig "$kc" -n istio-eastwest get svc istio-eastwestgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [[ -n "$ip" ]] && break
    sleep 10
  done
done

echo "== §9a RBAC istio-reader"
for kc in "$KUBECONFIG_EAST" "$KUBECONFIG_WEST"; do
  oc --kubeconfig "$kc" create serviceaccount istio-reader-service-account -n istio-system 2>/dev/null || true
  oc --kubeconfig "$kc" adm policy add-cluster-role-to-user cluster-reader -z istio-reader-service-account -n istio-system
done

echo "== §9b–c Remote secrets (ROSA TLS patch)"
oc --kubeconfig "$KUBECONFIG_WEST" config set-context --current --namespace=istio-system
oc --kubeconfig "$KUBECONFIG_EAST" config set-context --current --namespace=istio-system

istioctl create-remote-secret \
  --kubeconfig="$KUBECONFIG_WEST" \
  -n istio-system \
  -i istio-system \
  --name=cluster2 \
  --create-service-account=false >"$TMP/raw-west-to-east.yaml"
python3 "$PATCHER" cluster2 "$TMP/raw-west-to-east.yaml" "$TMP/fixed-west-to-east.yaml"
oc_east apply -f "$TMP/fixed-west-to-east.yaml"

istioctl create-remote-secret \
  --kubeconfig="$KUBECONFIG_EAST" \
  -n istio-system \
  -i istio-system \
  --name=cluster1 \
  --create-service-account=false >"$TMP/raw-east-to-west.yaml"
python3 "$PATCHER" cluster1 "$TMP/raw-east-to-west.yaml" "$TMP/fixed-east-to-west.yaml"
oc_west apply -f "$TMP/fixed-east-to-west.yaml"

echo "== Verification quick checks"
oc_east get secret -n istio-system -l istio/multiCluster=true
oc_west get secret -n istio-system -l istio/multiCluster=true
oc_east -n istio-eastwest get svc istio-eastwestgateway
oc_west -n istio-eastwest get svc istio-eastwestgateway

rm -rf "$TMP"
echo ""
echo "Day 1 infra steps completed."
echo "Next: optional Gateway API ingress (provisioning §10–11), then docs/ossm-mesh-applications-and-routing.md"
echo "Check istiod logs if needed: oc logs deploy/istiod -n istio-system | grep -i x509"
