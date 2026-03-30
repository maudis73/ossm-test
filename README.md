# OSSM 3.3 — Multi-cluster PoC (two ROSA clusters)

Hands-on material for **OpenShift Service Mesh 3.3**: **multi-primary, multi-network** mesh on **two ROSA** clusters, shared PKI, **east–west** gateways, **remote secrets**, optional **Gateway API** north–south ingress on **East and West**, and **sample** apps with **namespace sameness**. It aligns with Red Hat **Chapter 6** (multi-cluster); details, checkpoints, and ROSA-specific notes are in the docs below.

**Official product docs:** [Multi-cluster topologies](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.3/html/installing/ossm-multi-cluster-topologies) · [Installing Service Mesh](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.3/html/installing/ossm-installing-service-mesh) · [Gateways](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.3/html/gateways/ossm-gateways)

---

## Day 1 — Step by step

Use this as a **checklist**. Every command and YAML block lives in the linked guides—do not skip the checkpoints there.

### 1. Clone and open the repo

```bash
git clone https://github.com/maudis73/ossm-test.git
cd ossm-test
```

### 2. Know the two runbooks

| Order | Document | Purpose |
| ----- | -------- | ------- |
| First | [docs/ossm-multi-cluster-mesh-provisioning.md](docs/ossm-multi-cluster-mesh-provisioning.md) | Operators, **Istio CNI**, PKI / **`cacerts`**, **`Istio` CR**, east–west, remote secrets, ingress §10–11 |
| Second | [docs/ossm-mesh-applications-and-routing.md](docs/ossm-mesh-applications-and-routing.md) | **`sample`** workloads, cross-cluster curls, **`HTTPRoute`** / **`ReferenceGrant`**, cleanup |

The short index [docs/ossm-32-namespace-sameness-poc.md](docs/ossm-32-namespace-sameness-poc.md) is optional—it only summarizes the same split.

### 3. Local and cluster prerequisites

Confirm from **§1** in the provisioning doc:

- Two ROSA clusters, **cluster-admin** on both
- **`oc`** and **`istioctl`** on your workstation (**Istio 1.28.5** for this PoC—see **§2**)
- East–west path **15443** between gateway LoadBalancers; APIs reachable for remote secrets (see **Appendix A**)

### 4. Per-run config (not committed)

```bash
cp config/demo-params.example.yaml config/demo-params.yaml
```

Edit **`config/demo-params.yaml`** for your **`cluster_name`**, **`network`**, **`mesh.id`**, ingress hostnames, and **`ISTIO_VERSION`**. The file is **gitignored**—do not commit secrets or kubeconfig paths you consider sensitive.

### 5. Install operator and Istio CNI on **both** clusters

Follow **§1b** in the provisioning doc **on East, then on West** (subscription, CSV, **`IstioCNI`** in **`istio-cni`**). **Do not** create the **`Istio`** control-plane CR until **`cacerts`** is applied (**§4**), as the runbook describes.

Optional: **§1c** — apply [`manifests/console/east-console-notification.yaml`](manifests/console/east-console-notification.yaml) on East and [`manifests/console/west-console-notification.yaml`](manifests/console/west-console-notification.yaml) on West so the web console shows which cluster you are using.

### 6. Mesh PKI and `cacerts`

- **§3** — generate **`east/`** and **`west/`** cert material on the workstation (OpenSSL).
- **§4** — create the **`cacerts`** secret on **both** clusters before **`Istio`**.

### 7. Control plane and east–west on each cluster

In order: **§5–8** — **`Istio` CR** and east–west gateway / **`expose-services`** on **East**, then the same pattern on **West**. Use the verification blocks after each section.

### 8. Remote secrets (bidirectional)

Complete **§9** on both sides, including RBAC (**§9a**), **`istioctl create-remote-secret`** (**§9b**), and the **§9c** ROSA TLS note if istiod logs show **`x509: certificate signed by unknown authority`**.

### 9. Optional north–south ingress (Gateway API)

**§10** (East) and **§11** (West) with [`manifests/east/`](manifests/east/) and [`manifests/west/`](manifests/west/). Cross-namespace routes need **`ReferenceGrant`** manifests under [`manifests/sample/`](manifests/sample/).

### 10. Applications and routing

When infra is ready, follow [docs/ossm-mesh-applications-and-routing.md](docs/ossm-mesh-applications-and-routing.md) for **`sample`**, helloworld, and **`HTTPRoute`** examples.

---

## Automated Day 1 (`scripts/day1-deploy.sh`)

The script runs provisioning **[§1b through §9](docs/ossm-multi-cluster-mesh-provisioning.md)** on **both** clusters. **Step-by-step commands** (login, env vars, verification, manual fallback) are in **[Repeat deployment — exact command flow](#repeat-deployment--exact-command-flow)** below.

**Not covered by the script:** Gateway API ingress (**§10–11**) and the [applications doc](docs/ossm-mesh-applications-and-routing.md).

---

## Repeat deployment — exact command flow

Use this to reproduce what the automation does on **two ROSA clusters** (East + West). Adjust API URLs and paths to match your environment.

### 1) Workstation checks

```bash
oc version --client
istioctl version --remote=false   # should match Istio line shipped by OSSM (e.g. 1.28.x)
command -v openssl python3
python3 -c "import yaml"          # PyYAML; e.g. Fedora: sudo dnf install python3-pyyaml
```

Set the Istio version used in heredocs and **`IstioCNI`** / **`Istio` CR** (no leading `v` in the variable):

```bash
cd /path/to/ossm-test
export ISTIO_VERSION=1.28.5
```

### 2) Log in to **each** cluster into **separate** kubeconfig files

Do **not** use one file for both clusters unless you merge contexts by hand. Example: repo-local files (already in **`.gitignore`**):

```bash
mkdir -p .kube

# East — paste password at prompt (or use a token from the console)
oc login https://api.YOUR_EAST_SUBDOMAIN.p1.openshiftapps.com:443 \
  -u cluster-admin \
  --kubeconfig="$(pwd)/.kube/config-east"

# West
oc login https://api.YOUR_WEST_SUBDOMAIN.p1.openshiftapps.com:443 \
  -u cluster-admin \
  --kubeconfig="$(pwd)/.kube/config-west"
```

Verify:

```bash
oc --kubeconfig="$(pwd)/.kube/config-east" get ns | head
oc --kubeconfig="$(pwd)/.kube/config-west" get ns | head
```

Export paths for the script:

```bash
export KUBECONFIG_EAST="$(pwd)/.kube/config-east"
export KUBECONFIG_WEST="$(pwd)/.kube/config-west"
```

**Security:** never commit kubeconfigs or passwords. **`new-rosa.txt`**-style credential files should stay **gitignored** or off disk after use.

### 3) Run the full Day 1 script

This performs, in order: **Subscription** (Service Mesh operator) on both clusters → wait for CSV **Succeeded** → **`istio-cni`** project + **`IstioCNI`** → mesh PKI under **`./ossm-mesh-certs`** (unless already present) → **`istio-system`** + **`cacerts`** (East `network1`, West `network2`) → **`Istio`** CR (`cluster1` / `cluster2`, **`mesh1`**) → east–west gateway YAML from sail-operator + **expose-services** → **`cluster-reader`** for **`istio-reader-service-account`** → **remote secrets** (with ROSA TLS patch).

```bash
# optional: export PKI_DIR="$HOME/ossm-mesh-certs"
./scripts/day1-deploy.sh
# optional: ./scripts/day1-deploy.sh --with-console
# reuse PKI from a previous run: ./scripts/day1-deploy.sh --skip-pki
```

The script **updates** both kubeconfigs: **`oc config set-context --current --namespace=istio-system`** on each (helps **`istioctl`**). It **deletes and recreates** **`cacerts`** if the secret already exists.

### 4) Remote secrets — if `istioctl` fails (`istio-reader-service-account.default` not found)

**Current `day1-deploy.sh`** passes **`-n istio-system`** and **`-i istio-system`** to **`istioctl`**. If you use older notes or a custom command, **`istioctl`** may look for the reader **ServiceAccount** in **`default`**. Apply secrets manually (ROSA **§9c** TLS workaround):

```bash
REPO="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# West → East: istioctl reads WEST kubeconfig; oc applies on EAST
istioctl create-remote-secret \
  --kubeconfig="$KUBECONFIG_WEST" \
  -n istio-system \
  -i istio-system \
  --name=cluster2 \
  --create-service-account=false >"$TMP/raw-we.yaml"

python3 "$REPO/scripts/rosa-patch-remote-secret.py" cluster2 "$TMP/raw-we.yaml" "$TMP/fix-we.yaml"
oc --kubeconfig="$KUBECONFIG_EAST" apply -f "$TMP/fix-we.yaml"

# East → West
istioctl create-remote-secret \
  --kubeconfig="$KUBECONFIG_EAST" \
  -n istio-system \
  -i istio-system \
  --name=cluster1 \
  --create-service-account=false >"$TMP/raw-ew.yaml"

python3 "$REPO/scripts/rosa-patch-remote-secret.py" cluster1 "$TMP/raw-ew.yaml" "$TMP/fix-ew.yaml"
oc --kubeconfig="$KUBECONFIG_WEST" apply -f "$TMP/fix-ew.yaml"
```

On **non-ROSA** clusters you can often **`oc apply -f`** the raw **`istioctl`** output without the Python step (see [provisioning doc §9](docs/ossm-multi-cluster-mesh-provisioning.md)).

### 5) Verification (same checks used after deploy)

**East–west gateway** (should be **`1/1`** **Available**, **LoadBalancer** hostname, pod **Running**):

```bash
oc --kubeconfig="$KUBECONFIG_EAST" -n istio-system get deploy,svc -l istio=eastwestgateway
oc --kubeconfig="$KUBECONFIG_EAST" -n istio-system get pods -l istio=eastwestgateway
oc --kubeconfig="$KUBECONFIG_WEST" -n istio-system get deploy,svc -l istio=eastwestgateway
```

**Remote secrets:**

```bash
oc --kubeconfig="$KUBECONFIG_EAST" get secret -n istio-system -l istio/multiCluster=true
oc --kubeconfig="$KUBECONFIG_WEST" get secret -n istio-system -l istio/multiCluster=true
```

**istiod** (expect no **`x509`** / **`forbidden`** spam):

```bash
oc --kubeconfig="$KUBECONFIG_EAST" logs deploy/istiod -n istio-system --tail=30 | grep -iE 'x509|forbidden' || true
oc --kubeconfig="$KUBECONFIG_WEST" logs deploy/istiod -n istio-system --tail=30 | grep -iE 'x509|forbidden' || true
```

### 6) Optional next steps (not run by `day1-deploy.sh`)

**Gateway API** north–south on each cluster (provisioning **§10–§11**):

```bash
oc --kubeconfig="$KUBECONFIG_EAST" apply -k manifests/east/
oc --kubeconfig="$KUBECONFIG_WEST" apply -k manifests/west/
# cross-namespace backends to sample namespace, as in the doc:
oc --kubeconfig="$KUBECONFIG_EAST" apply -f manifests/sample/referencegrant-helloworld.yaml
oc --kubeconfig="$KUBECONFIG_WEST" apply -f manifests/sample/referencegrant-west-ingress.yaml
```

Then follow [docs/ossm-mesh-applications-and-routing.md](docs/ossm-mesh-applications-and-routing.md) for **`sample`** / helloworld.

### PKI-only helper (equivalent to script §3)

To generate **`east/`** and **`west/`** trees without the full deploy:

```bash
export PKI_DIR="$PWD/ossm-mesh-certs"
FORCE_PKI=1 bash scripts/generate-mesh-pki.sh
```

---

## Repo layout

| Path | Contents |
| ---- | -------- |
| `docs/` | Provisioning runbook, applications runbook, small index |
| `config/demo-params.example.yaml` | Example mesh/ingress parameters (copy to `demo-params.yaml`) |
| `manifests/east/`, `manifests/west/` | Gateway API ingress samples |
| `manifests/sample/` | **`ReferenceGrant`** helpers |
| `manifests/console/` | Optional **`ConsoleNotification`** banners |
| `scripts/` | **`day1-deploy.sh`**, PKI generator, ROSA remote-secret patcher |

**.gitignore** excludes local kubeconfig trees, PKI directories, `*-cert` stubs, and **`config/demo-params.yaml`**.

---

## Contributing / fork

Replace **`maudis73/ossm-test`** in clone URLs with your fork if applicable. Push with a GitHub **PAT** or **SSH** as you prefer.
