# Lab 1 (Part 2): Init Containers & Multi-Container Pods
### Composing Pods — Ordered Setup, Sidecars, and Native Sidecars
**Intermediate Kubernetes — Pods Deep Dive (companion to Module 1)**

---

## Lab Overview

### What You Will Do

- Use an **init container** to prepare state before the app container starts
- Build a **multi-container Pod** where a **sidecar** shares a volume and the network with the main container
- Use a **native sidecar** (an init container with `restartPolicy: Always`, stable in 1.29+) as a log shipper
- Inspect per-container logs and exec into a specific container

### Why this matters

A Pod is not "one container" — it's a group of containers that share a network namespace (they reach each other on `localhost`), can share volumes, and are co-scheduled and co-located. That shared context is what makes **init containers** and **sidecars** possible, and both are everyday tools for application developers.

### Prerequisites

- Completion of Lab 1 with `kubectl` and cluster access configured

### Duration

Approximately 25-35 minutes

---

## Environment Setup

```bash
cd ~/environment/custom_k8s/labs/lab-01-pods
export STUDENT_NAME=<usernumber>
echo "Student: $STUDENT_NAME"
kubectl create namespace lab-pods-$STUDENT_NAME
kubectl config set-context --current --namespace=lab-pods-$STUDENT_NAME
```

---

## Step 1: Init Container — Ordered Setup

Init containers run **to completion, in order, before any app container starts**. If an init container fails, the Pod restarts it until it succeeds — the app containers never start until every init container has finished.

Here the init container writes an HTML page into a shared `emptyDir` volume, then nginx serves it:

```bash
envsubst '$STUDENT_NAME' < init-container-pod.yaml | kubectl apply -f -

# Watch the Init phase, then Running (Ctrl-C once it's Running)
kubectl get pod init-demo -n lab-pods-$STUDENT_NAME -w
```

While it starts you'll briefly see `Init:0/1`, then `PodInitializing`, then `Running`. Inspect what happened:

```bash
# The init container ran to completion
kubectl get pod init-demo -n lab-pods-$STUDENT_NAME \
  -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}{"\n"}'

# Its logs (note the -c to select a container)
kubectl logs init-demo -n lab-pods-$STUDENT_NAME -c setup

# The app serves the content the init container prepared
kubectl exec init-demo -n lab-pods-$STUDENT_NAME -c web -- curl -s localhost:80
```

> ✅ **Checkpoint:** The init container's state is **`Completed`**, its logs show `init container finished`, and nginx serves the page **"written by the init container"** — proof the init container ran first and set things up for the app.

---

## Step 2: Multi-Container Pod — the Sidecar Pattern

A **sidecar** is a helper container that runs **alongside** the main container in the same Pod, extending it. Here a `content-sync` sidecar regenerates the page every 10 seconds, and nginx serves it from the **shared volume** — they cooperate through `emptyDir`:

```bash
envsubst '$STUDENT_NAME' < sidecar-pod.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready pod/sidecar-demo -n lab-pods-$STUDENT_NAME --timeout=60s

# Two containers, both Ready (READY column shows 2/2)
kubectl get pod sidecar-demo -n lab-pods-$STUDENT_NAME
kubectl get pod sidecar-demo -n lab-pods-$STUDENT_NAME \
  -o jsonpath='{.spec.containers[*].name}{"\n"}'
```

Observe the two containers cooperating:

```bash
# The sidecar's logs vs the web container's logs (-c selects the container)
kubectl logs sidecar-demo -n lab-pods-$STUDENT_NAME -c content-sync --tail=2

# nginx serves what the sidecar wrote to the shared volume
kubectl exec sidecar-demo -n lab-pods-$STUDENT_NAME -c web -- curl -s localhost:80

# Run it again after ~10s — the timestamp changes because the sidecar refreshed it
kubectl exec sidecar-demo -n lab-pods-$STUDENT_NAME -c web -- curl -s localhost:80
```

> ✅ **Checkpoint:** The Pod shows **`2/2`** Ready. nginx serves **"refreshed by the sidecar"**, and the timestamp advances between requests — two containers sharing one volume, running concurrently in one Pod. They'd also reach each other over `localhost`.

---

## Step 3: Native Sidecars (1.29+)

A plain sidecar (Step 2) has two limitations: it isn't guaranteed to be **running before** the app starts, and it keeps a Job/Pod from ever "completing." A **native sidecar** fixes both — it's an **init container with `restartPolicy: Always`**. It starts before the app containers, stays running alongside them, and doesn't block Pod completion. This is the modern pattern for log shippers, proxies, and config agents.

```bash
envsubst '$STUDENT_NAME' < native-sidecar-pod.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready pod/native-sidecar-demo -n lab-pods-$STUDENT_NAME --timeout=60s

# The sidecar is declared under initContainers, but with restartPolicy: Always
kubectl get pod native-sidecar-demo -n lab-pods-$STUDENT_NAME \
  -o jsonpath='{.spec.initContainers[0].name}: restartPolicy={.spec.initContainers[0].restartPolicy}{"\n"}'
```

The `log-shipper` sidecar started first and is tailing the app's log file — its stdout is the app's forwarded logs:

```bash
sleep 10
kubectl logs native-sidecar-demo -n lab-pods-$STUDENT_NAME -c log-shipper
```

> ✅ **Checkpoint:** `restartPolicy=Always` on an init container, and `kubectl logs -c log-shipper` shows **`app event N`** lines — the sidecar came up first and is streaming the app's log, exactly what a real log-forwarding sidecar does.

---

## When to Use Which

| Need | Use |
|------|-----|
| One-time setup / wait for a dependency before the app starts | **Init container** (runs to completion, then exits) |
| A helper that runs *for the life of* the app (proxy, log shipper, cache warmer) | **Native sidecar** (`initContainers` + `restartPolicy: Always`) |
| Two peers cooperating, ordering not critical | **Plain multi-container Pod** |

---

## Step 4: Clean Up

```bash
kubectl delete namespace lab-pods-$STUDENT_NAME
```

---

## Summary

- A Pod is a group of co-scheduled containers sharing a **network namespace** (`localhost`) and, optionally, **volumes**.
- **Init containers** run to completion, in order, **before** app containers — use them for setup and dependency gating.
- **Sidecars** run **alongside** the main container to extend it (logging, proxying, content sync).
- **Native sidecars** (`initContainers` + `restartPolicy: Always`, 1.29+) start before the app, run for its lifetime, and don't block Pod completion.
- `kubectl logs -c <container>` and `kubectl exec ... -c <container>` target a specific container in a multi-container Pod.
