# OSSM 3.3 — Mesh applications and ingress routing

This document is the **application and routing** companion to [ossm-multi-cluster-mesh-provisioning.md](ossm-multi-cluster-mesh-provisioning.md). Complete **operators, `cacerts`, `Istio` CRs, east–west gateways, remote secrets**, and (if you use them) **Gateway API ingress** on each cluster **before** the steps here.

| Section | What |
| ------- | ---- |
| § 1 | **`sample`** — helloworld, sleep, cross-cluster load balancing |
| § 2 | **Live migration** (helloworld East → West) |
| § 3 | **Optional cleanup** (`sample`, full mesh pointers) |
| § 4 | **HTTPRoute** examples — north–south to mesh `Service`s (repo manifests) |

**How to read command blocks:** Subsections are labeled **Run on: East** or **Run on: West**. Point **`oc`** at that cluster using your normal login or context—this doc does not prescribe kubeconfig file names.

---

## 1) Cross-cluster load balancing PoC (`sample`)

This section deploys the same application (helloworld v1) on both clusters to verify **cross-cluster load balancing**. Each cluster's deployment sets a custom `SERVICE_VERSION` environment variable (`v1-east` / `v1-west`) so the response identifies which cluster served the request.

### Create namespace + injection

**Run on: East**

```bash
oc get project sample || oc new-project sample
oc label namespace sample istio-injection=enabled --overwrite
```

**Run on: West**

```bash
oc get project sample || oc new-project sample
oc label namespace sample istio-injection=enabled --overwrite
```

### Deploy helloworld Service (both clusters)

The Service definition is the same on both clusters (from upstream samples):

**Run on: East**

```bash
oc apply -n sample \
  -f https://raw.githubusercontent.com/openshift-service-mesh/istio/release-1.28/samples/helloworld/helloworld.yaml \
  -l service=helloworld
```

**Run on: West**

```bash
oc apply -n sample \
  -f https://raw.githubusercontent.com/openshift-service-mesh/istio/release-1.28/samples/helloworld/helloworld.yaml \
  -l service=helloworld
```

### East — `helloworld` v1 (tagged `v1-east`) + `sleep` — **Run on: East**

The Deployment uses the v1 image but overrides `SERVICE_VERSION` to include the cluster name:

```bash
cat <<'EOF' | oc apply -n sample -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld-v1
  labels:
    app: helloworld
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: helloworld
      version: v1
  template:
    metadata:
      labels:
        app: helloworld
        version: v1
    spec:
      containers:
      - name: helloworld
        image: quay.io/sail-dev/examples-helloworld-v1:1.0
        env:
        - name: SERVICE_VERSION
          value: "v1-east"
        resources:
          requests:
            cpu: "100m"
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5000
EOF

oc apply -n sample \
  -f https://raw.githubusercontent.com/openshift-service-mesh/istio/release-1.28/samples/sleep/sleep.yaml
```

### West — `helloworld` v1 (tagged `v1-west`) + `sleep` — **Run on: West**

Same image, different `SERVICE_VERSION`:

```bash
cat <<'EOF' | oc apply -n sample -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld-v1
  labels:
    app: helloworld
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: helloworld
      version: v1
  template:
    metadata:
      labels:
        app: helloworld
        version: v1
    spec:
      containers:
      - name: helloworld
        image: quay.io/sail-dev/examples-helloworld-v1:1.0
        env:
        - name: SERVICE_VERSION
          value: "v1-west"
        resources:
          requests:
            cpu: "100m"
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5000
EOF

oc apply -n sample \
  -f https://raw.githubusercontent.com/openshift-service-mesh/istio/release-1.28/samples/sleep/sleep.yaml
```

### Wait

**Run on: East**

```bash
oc wait --for=condition=available -n sample deployment/helloworld-v1 --timeout=5m
oc wait --for=condition=available -n sample deployment/sleep --timeout=5m
```

**Run on: West**

```bash
oc wait --for=condition=available -n sample deployment/helloworld-v1 --timeout=5m
oc wait --for=condition=available -n sample deployment/sleep --timeout=5m
```

### Curl

With **`oc`** aimed at **East**, run several requests from **sleep** on East:

```bash
for i in {1..10}; do
  oc exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello
done
```

Aim **`oc`** at **West** and run the same loop from **sleep** on West:

```bash
for i in {1..10}; do
  oc exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello
done
```

You should see responses from **both** clusters in each test, confirming cross-cluster load balancing:

```
Hello version: v1-east, instance: helloworld-v1-59cf54b444-7czgm
Hello version: v1-west, instance: helloworld-v1-56b9bcdd6-zbsxk
Hello version: v1-east, instance: helloworld-v1-59cf54b444-7czgm
...
```

---

## 2) Live migration test (**Run on: East** / **Run on: West**)

This test proves the mesh automatically redirects traffic when an application moves from one cluster to another, with no client reconfiguration.

**Scenario:** helloworld runs only on East. A continuous curl loop runs from East's sleep pod. While the loop runs, we deploy helloworld on West and remove it from East. The responses should transition from `v1-east` to `v1-west`.

### Setup: helloworld on East only

If helloworld is currently deployed on both clusters (from § 1), remove it from West:

**Run on: West**

```bash
oc delete deployment helloworld-v1 -n sample
```

Verify only East has helloworld:

```bash
# Run on: East
oc get deploy -n sample
# Run on: West
oc get deploy -n sample
```

Wait ~15 seconds for the mesh to converge, then confirm only `v1-east` responses (**`oc`** on East):

```bash
for i in {1..3}; do
  oc exec -n sample deploy/sleep -c sleep -- curl -sS helloworld.sample:5000/hello
done
```

### Start continuous curl loop

**Run on: East** — start a curl loop that logs responses with timestamps:

```bash
oc exec -n sample deploy/sleep -c sleep -- \
  sh -c 'while true; do echo "$(date +%H:%M:%S) $(curl -sS helloworld.sample:5000/hello 2>&1)"; sleep 2; done'
```

Leave this running. You should see only `v1-east` responses.

### Migrate: deploy on West + delete from East

Use **`oc`** on **West** to apply the Deployment, and **`oc`** on **East** to delete it—often easiest with **two shells** (or switch context between commands). Run both as close together as your process allows.

**Deploy on West** (**`oc`** → West):

```bash
cat <<'EOF' | oc apply -n sample -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld-v1
  labels:
    app: helloworld
    version: v1
spec:
  replicas: 1
  selector:
    matchLabels:
      app: helloworld
      version: v1
  template:
    metadata:
      labels:
        app: helloworld
        version: v1
    spec:
      containers:
      - name: helloworld
        image: quay.io/sail-dev/examples-helloworld-v1:1.0
        env:
        - name: SERVICE_VERSION
          value: "v1-west"
        resources:
          requests:
            cpu: "100m"
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 5000
EOF
```

**Run on: East** — delete the Deployment (often in parallel with apply on West):

```bash
oc delete deployment helloworld-v1 -n sample
```

### Expected output

Watch the curl loop terminal. You should see a transition like:

```
06:29:45  Hello version: v1-east, instance: helloworld-v1-59cf54b444-7czgm
06:29:47  Hello version: v1-east, instance: helloworld-v1-59cf54b444-7czgm
06:29:50  no healthy upstream
06:29:52  no healthy upstream
06:29:54  no healthy upstream
06:29:56  Hello version: v1-west, instance: helloworld-v1-56b9bcdd6-t4rp7
06:29:58  Hello version: v1-west, instance: helloworld-v1-56b9bcdd6-t4rp7
06:30:00  Hello version: v1-west, instance: helloworld-v1-56b9bcdd6-t4rp7
```

The brief `no healthy upstream` window (~6 seconds) occurs because we deleted East before West was fully ready. In a production migration, you would deploy on West first, wait for it to become healthy, then remove from East (blue-green) to achieve zero downtime.

Press `Ctrl-C` to stop the curl loop when done.

---

## 3) Optional cleanup

**`sample` namespace (East / West):**

```bash
# Run on: East
oc delete ns sample --ignore-not-found
# Run on: West
oc delete ns sample --ignore-not-found
```

**Ingress-only namespaces** (for example `east-ingress`, or `west-ingress` if you created them) can be removed separately when you no longer need north–south entry on that cluster.

**Full control-plane / mesh teardown** (both clusters) follows Red Hat **§ 6.3.2**—see [ossm-multi-cluster-mesh-provisioning.md](ossm-multi-cluster-mesh-provisioning.md) for context and links. Illustrative commands:

```bash
# East
oc delete istio/default ns/istio-system ns/sample ns/istio-cni
# West
oc delete istio/default ns/istio-system ns/sample ns/istio-cni
```

Adjust namespaces (`east-ingress`, `west-ingress`, `istio-cni`, etc.) to match what you actually created.

---

## 4) North–south `HTTPRoute` to mesh services (examples in this repo)

After [§ 10–11 in the provisioning guide](ossm-multi-cluster-mesh-provisioning.md) (Gateway API `Gateway` + **LoadBalancer**), attach **`HTTPRoute`** resources with **`parentRefs`** to that `Gateway`. Rules map **paths** to **`Service` `backendRefs`**.

**East ingress**

| File | Role |
| ---- | ---- |
| [`manifests/east/httproute.yaml`](../manifests/east/httproute.yaml) | Rules: `/status`, `/headers` → **`httpbin`** (separate **rules**—each rule’s `matches` list is **AND**ed). `/hello` → **`helloworld`** in **`sample`**. |
| [`manifests/sample/referencegrant-helloworld.yaml`](../manifests/sample/referencegrant-helloworld.yaml) | **`ReferenceGrant`** in **`sample`** for `HTTPRoute` in **`east-ingress`** → **`Service/helloworld`**. |

**West ingress**

| File | Role |
| ---- | ---- |
| [`manifests/west/httproute.yaml`](../manifests/west/httproute.yaml) | Same path split as East; listener host **`west-ingress.example.com`**. |
| [`manifests/sample/referencegrant-west-ingress.yaml`](../manifests/sample/referencegrant-west-ingress.yaml) | **`ReferenceGrant`** for `HTTPRoute` in **`west-ingress`**. |

Apply order: gateway bundle (`oc apply -k manifests/east/` or `manifests/west/`), then the matching **`ReferenceGrant`** if you use **`/hello`** to **`sample/helloworld`**.

**Client check (East)** — listener host from [`manifests/east/gateway.yaml`](../manifests/east/gateway.yaml):

```bash
export INGRESS_HOST=$(oc get gtw east-ingress -n east-ingress -o jsonpath='{.status.addresses[0].value}')
curl -sS -H 'Host: east-ingress.example.com' "http://${INGRESS_HOST}/hello"
```

**Client check (West)** — **`oc`** on West; host from [`manifests/west/gateway.yaml`](../manifests/west/gateway.yaml):

```bash
export INGRESS_HOST=$(oc get gtw west-ingress -n west-ingress -o jsonpath='{.status.addresses[0].value}')
curl -sS -H 'Host: west-ingress.example.com' "http://${INGRESS_HOST}/hello"
```

For more detail on Gateway API behavior, see [OpenShift Service Mesh — Gateways](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.3/html/gateways/ossm-gateways).
