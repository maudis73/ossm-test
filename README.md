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

## Repo layout

| Path | Contents |
| ---- | -------- |
| `docs/` | Provisioning runbook, applications runbook, small index |
| `config/demo-params.example.yaml` | Example mesh/ingress parameters (copy to `demo-params.yaml`) |
| `manifests/east/`, `manifests/west/` | Gateway API ingress samples |
| `manifests/sample/` | **`ReferenceGrant`** helpers |
| `manifests/console/` | Optional **`ConsoleNotification`** banners |

**.gitignore** excludes local kubeconfig trees, PKI directories, `*-cert` stubs, and **`config/demo-params.yaml`**.

---

## Contributing / fork

Replace **`maudis73/ossm-test`** in clone URLs with your fork if applicable. Push with a GitHub **PAT** or **SSH** as you prefer.
