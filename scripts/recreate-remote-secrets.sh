#!/usr/bin/env bash
# Recreate multicluster remote secrets (bidirectional) with ROSA TLS patch.
# Requires: mesh installed, istio-reader SA + cluster-reader, istio-system on both clusters.
#
# One kubeconfig must define two contexts (defaults: cluster-east, cluster-west):
#
#   export KUBECONFIG=/path/to/merged-config   # optional; defaults to ~/.kube/config
#   # optional overrides: CONTEXT_EAST CONTEXT_WEST
#   ./scripts/recreate-remote-secrets.sh
#
set -euo pipefail

KCFG="${KUBECONFIG:-$HOME/.kube/config}"
CONTEXT_EAST="${CONTEXT_EAST:-cluster-east}"
CONTEXT_WEST="${CONTEXT_WEST:-cluster-west}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHER="$REPO_ROOT/scripts/rosa-patch-remote-secret.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

need_cmd() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
need_cmd oc
need_cmd istioctl
need_cmd python3
python3 -c "import yaml" 2>/dev/null || { echo "Install PyYAML: pip install pyyaml or dnf install python3-pyyaml" >&2; exit 1; }

oc_east() { oc --kubeconfig="$KCFG" --context="$CONTEXT_EAST" "$@"; }
oc_west() { oc --kubeconfig="$KCFG" --context="$CONTEXT_WEST" "$@"; }

echo "Using kubeconfig: $KCFG (contexts: $CONTEXT_EAST, $CONTEXT_WEST)"
echo "Preflight: API + istio-system + reader SA"
oc_east get ns istio-system >/dev/null
oc_west get ns istio-system >/dev/null
oc_east get sa istio-reader-service-account -n istio-system >/dev/null
oc_west get sa istio-reader-service-account -n istio-system >/dev/null

echo "West -> East (secret istio-remote-secret-cluster2 on East)"
istioctl create-remote-secret \
  --kubeconfig="$KCFG" \
  --context="$CONTEXT_WEST" \
  -n istio-system \
  -i istio-system \
  --name=cluster2 \
  --create-service-account=false >"$TMP/raw-we.yaml"
python3 "$PATCHER" cluster2 "$TMP/raw-we.yaml" "$TMP/fix-we.yaml"
oc_east apply -f "$TMP/fix-we.yaml"

echo "East -> West (secret istio-remote-secret-cluster1 on West)"
istioctl create-remote-secret \
  --kubeconfig="$KCFG" \
  --context="$CONTEXT_EAST" \
  -n istio-system \
  -i istio-system \
  --name=cluster1 \
  --create-service-account=false >"$TMP/raw-ew.yaml"
python3 "$PATCHER" cluster1 "$TMP/raw-ew.yaml" "$TMP/fix-ew.yaml"
oc_west apply -f "$TMP/fix-ew.yaml"

echo "Done."
oc_east get secret -n istio-system -l istio/multiCluster=true
oc_west get secret -n istio-system -l istio/multiCluster=true
