# OSSM 3.3 PoC: Namespace sameness (index)

This proof-of-concept is split into two documents:

| Document | Scope |
| -------- | ----- |
| [ossm-multi-cluster-mesh-provisioning.md](ossm-multi-cluster-mesh-provisioning.md) | **Infrastructure:** operators, **Istio CNI**, mesh PKI / **`cacerts`**, **`Istio` / istiod** on East and West, **east–west gateways**, **`expose-services`**, **remote secrets** (with ROSA TLS note), **north–south** via **Gateway API** on **each** cluster ([`manifests/east/`](../manifests/east/), [`manifests/west/`](../manifests/west/)), appendices for **networking / troubleshooting**. |
| [ossm-mesh-applications-and-routing.md](ossm-mesh-applications-and-routing.md) | **Applications:** **`sample`** (helloworld, sleep), cross-cluster checks, migration demo, cleanup, and **`HTTPRoute`** examples pointing at mesh `Service`s (paths under [`manifests/`](../manifests/)). |

**Topology:** two ROSA clusters (East = `cluster1` / `network1`, West = `cluster2` / `network2`), multi-primary multi-network, namespace sameness for workloads like **`helloworld.sample`**.

**Per-run settings:** [`config/demo-params.example.yaml`](../config/demo-params.example.yaml) → `config/demo-params.yaml` (gitignored).

**Ingress:** provisioning guide **§ 10** (East) and **§ 11** (West). This file replaces the former single mega-runbook; bookmark the two links above.
