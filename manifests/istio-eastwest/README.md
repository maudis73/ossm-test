# `istio-eastwest` — cross-cluster gateway

Deploy **on each ROSA cluster** so **`istio-system`** stays control-plane-only (**istiod**, mesh secrets).

| Apply on | Path |
| -------- | ---- |
| East (`network1`) | `oc apply -k manifests/istio-eastwest/cluster1/` |
| West (`network2`) | `oc apply -k manifests/istio-eastwest/cluster2/` |

Each bundle creates **`Namespace/istio-eastwest`**, **`istio-eastwestgateway`** (Deployment/Service/LB **15443**), RBAC, and **`networking.istio.io/Gateway/cross-network-gateway`** in that namespace.

**Migrate from upstream sail-operator YAML in `istio-system`:** delete old east–west Deployment/Service/PDB/HPA/Role/RoleBinding/SA and **`cross-network-gateway`** in **`istio-system`** before applying this bundle.
