# Lab 6: Gateway API and HTTP Routing
### Gateways, HTTPRoutes, Host & Path Routing, and Weighted Traffic Splitting
**Intermediate Kubernetes — Module 6 of 13**

---

## Lab Overview

### What You Will Do

- Deploy two sample applications behind a Gateway
- Create a `GatewayClass` and a `Gateway` (each Gateway gets its own load balancer)
- Route by **hostname** with **weighted traffic splitting** (80/20) via an `HTTPRoute`
- Route by **path** (`/v1`, `/v2`) via a second `HTTPRoute`
- Apply an egress `NetworkPolicy` to restrict outbound traffic

### Why Gateway API (not Ingress)?

The **Gateway API** is the next-generation, role-oriented replacement for Ingress. Instead of one shared Ingress controller + a pile of controller-specific annotations, you get typed resources:

| Resource | Role | Analogy to Ingress |
|----------|------|--------------------|
| `GatewayClass` | cluster operator | the controller "flavor" (like an IngressClass) |
| `Gateway` | infra/platform | the listener + **its own load balancer** |
| `HTTPRoute` | app developer | the routing rules (host, path, weights, headers) |

The big practical difference: **each `Gateway` provisions its own load balancer** (here, via Envoy Gateway) — it does **not** share the ingress-nginx controller. Routing features that needed vendor annotations on Ingress (path rewrites, traffic splitting, header matching) are first-class fields in `HTTPRoute`.

### Prerequisites

- Completion of Lab 1 with `kubectl` and cluster access configured
- Gateway API CRDs + a Gateway controller installed (this platform runs **Envoy Gateway**)

### Duration

Approximately 30-40 minutes

---

## Environment Setup

```bash
cd ~/environment/custom_k8s/labs/lab-06
export STUDENT_NAME=<usernumber>
echo "Student: $STUDENT_NAME"
kubectl create namespace lab06-$STUDENT_NAME
kubectl config set-context --current --namespace=lab06-$STUDENT_NAME
```

Confirm the Gateway API is available and the controller is running:

```bash
kubectl get crd gatewayclasses.gateway.networking.k8s.io
kubectl get pods -n envoy-gateway-system
```

> ⚠️ If the CRD or controller is missing, notify the instructor.

---

## Step 1: Deploy Two Sample Applications

```bash
envsubst '$STUDENT_NAME' < app-v1.yaml | kubectl apply -f -
envsubst '$STUDENT_NAME' < app-v2.yaml | kubectl apply -f -

kubectl get pods -n lab06-$STUDENT_NAME -l app=web
kubectl get svc  -n lab06-$STUDENT_NAME
```

> ✅ **Checkpoint:** 4 pods (2 for v1, 2 for v2) Running, and 2 ClusterIP services — `app-v1-svc` and `app-v2-svc`, both on port 80.

---

## Step 2: Create the Gateway

A `GatewayClass` selects the controller; a `Gateway` defines a listener and gets **its own load balancer**.

```bash
envsubst '$STUDENT_NAME' < gateway.yaml | kubectl apply -f -

kubectl get gatewayclass lab-gateway-class-$STUDENT_NAME
kubectl get gateway lab-gateway -n lab06-$STUDENT_NAME
```

The load balancer takes ~1–2 minutes to provision. Wait for it and read its address:

```bash
kubectl wait --for=condition=Programmed gateway/lab-gateway -n lab06-$STUDENT_NAME --timeout=180s
GW=$(kubectl get gateway lab-gateway -n lab06-$STUDENT_NAME -o jsonpath='{.status.addresses[0].value}')
echo "Gateway load balancer: $GW"
```

> ✅ **Checkpoint:** `lab-gateway` is `PROGRAMMED=True` and has an `elb.amazonaws.com` address. This is **your Gateway's own** load balancer — separate from the ingress-nginx controller. (Compare: every student's Gateway gets a distinct LB.)

---

## Step 3: Host Routing with Weighted Traffic Splitting

Create an `HTTPRoute` that matches a hostname and splits traffic **80% to v1, 20% to v2**:

```bash
envsubst '$STUDENT_NAME' < httproute.yaml | kubectl apply -f -

# Verify the weights
kubectl get httproute app-route -n lab06-$STUDENT_NAME \
  -o jsonpath='{.spec.rules[0].backendRefs[*].weight}{"\n"}'
```

The route only matches the hostname `app-$STUDENT_NAME.lab.local` (a fake name), so send it via the `Host` header to your Gateway's LB:

```bash
# No matching hostname -> 404 from the Gateway
curl -s -o /dev/null -w "no Host header: HTTP %{http_code}\n" http://$GW/

# With the matching Host header -> watch the 80/20 split
for i in $(seq 1 10); do curl -s -H "Host: app-$STUDENT_NAME.lab.local" http://$GW/; echo; done
```

> ✅ **Checkpoint:** Without the `Host` header you get **404**. With `Host: app-$STUDENT_NAME.lab.local`, ~8 of 10 requests return **"Hello from App V1"** and ~2 return **"Hello from App V2"** — weighted splitting, served through your Gateway's own load balancer.

---

## Step 4: Path Routing

Add a second `HTTPRoute` on the **same Gateway** that routes by **path** instead of weight — `/v1` → app-v1, `/v2` → app-v2, everything else → app-v1:

```bash
envsubst '$STUDENT_NAME' < httproute-path.yaml | kubectl apply -f -

kubectl get httproute path-route -n lab06-$STUDENT_NAME \
  -o jsonpath='{range .spec.rules[*]}{.matches[0].path.value}{" -> "}{.backendRefs[0].name}{"\n"}{end}'
```

This route uses the hostname `path-$STUDENT_NAME.lab.local`. Test each path (longer prefixes win, so `/v1` and `/v2` beat the `/` default):

```bash
curl -s -H "Host: path-$STUDENT_NAME.lab.local" http://$GW/v1; echo   # App V1
curl -s -H "Host: path-$STUDENT_NAME.lab.local" http://$GW/v2; echo   # App V2
curl -s -H "Host: path-$STUDENT_NAME.lab.local" http://$GW/;   echo   # default -> App V1
```

> ✅ **Checkpoint:** `/v1` returns **"Hello from App V1"**, `/v2` returns **"Hello from App V2"**, and `/` falls through to **"Hello from App V1"** — all on the same Gateway, no annotations, just `HTTPRoute` path matches. Two HTTPRoutes (weighted + path) share one Gateway, dispatched by hostname.

---

## Step 5: Egress NetworkPolicy

NetworkPolicies also restrict **outbound** traffic. Create one that limits egress for pods labeled `run=egress-test` to DNS and in-namespace HTTP only:

```bash
envsubst '$STUDENT_NAME' < egress-policy.yaml | kubectl apply -f -

kubectl get networkpolicy restrict-egress -n lab06-$STUDENT_NAME
kubectl describe networkpolicy restrict-egress -n lab06-$STUDENT_NAME
```

> ✅ **Checkpoint:** The policy selects pods with `run=egress-test`, allows DNS (port 53) and in-namespace HTTP (port 80) egress only.

#### Test the policy

Deploy a pod the policy applies to (label `run=egress-test`) and confirm the **deny** — external egress is cut off the moment the policy exists:

```bash
kubectl run egress-test --image=curlimages/curl --labels="run=egress-test" \
  -n lab06-$STUDENT_NAME --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/egress-test -n lab06-$STUDENT_NAME --timeout=60s

# BLOCKED — external egress (neither DNS nor in-namespace): hangs, then fails
kubectl exec egress-test -n lab06-$STUDENT_NAME -- curl -s --max-time 5 https://1.1.1.1/ \
  && echo "reached (unexpected)" || echo ">>> external egress blocked (as expected)"

# ALLOWED paths the policy permits — DNS to kube-dns, and in-namespace HTTP
kubectl exec egress-test -n lab06-$STUDENT_NAME -- nslookup kubernetes.default
```

> ✅ **Checkpoint:** The external request **times out** — once an Egress policy exists, only the explicitly-allowed destinations are reachable, everything else is denied. (Requires a CNI that enforces NetworkPolicies, e.g. Calico.)

> **Real-world note:** the policy *allows* DNS and in-namespace HTTP, but whether those allow rules take effect — and whether **ClusterIP Service** traffic is matched at all — depends on how your CNI orders NetworkPolicy vs. kube-proxy's service NAT. On EKS with the VPC CNI + Calico this can be inconsistent, so the **deterministic** takeaway is: **external egress is denied**.

```bash
kubectl delete pod egress-test -n lab06-$STUDENT_NAME
```

---

## Step 6: Clean Up

```bash
# Delete the namespace first — this removes the Gateway and both HTTPRoutes.
# The GatewayClass carries a "gateway-exists" finalizer while any Gateway
# references it, so deleting the namespace first lets the GatewayClass delete
# complete instead of hanging.
kubectl delete namespace lab06-$STUDENT_NAME

# Now remove the cluster-scoped GatewayClass
kubectl delete gatewayclass lab-gateway-class-$STUDENT_NAME --timeout=60s 2>/dev/null
```

---

## Summary

| Concept | Resource | What it does |
|---------|----------|--------------|
| Controller selection | `GatewayClass` | Picks the Gateway controller (Envoy Gateway) |
| Listener + LB | `Gateway` | One listener (`:80`) and **its own load balancer** |
| Host + weighted routing | `HTTPRoute` | Matches a hostname, splits 80/20 across v1/v2 |
| Path routing | `HTTPRoute` | `/v1`, `/v2`, `/` dispatched to different backends |
| Outbound restriction | `NetworkPolicy` (Egress) | Denies external egress; allows DNS + in-namespace |

**Key takeaways:**
- The **Gateway API** replaces Ingress with typed, role-separated resources — no controller-specific annotations.
- Each **`Gateway` has its own load balancer**; you reach it directly, not through ingress-nginx.
- **`HTTPRoute`** does host matching, path matching, and weighted traffic splitting as first-class fields.
- An **Egress NetworkPolicy** is default-deny once it exists — only what you allow gets out.
