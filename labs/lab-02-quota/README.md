# Lab 2 (Part 4): Resource Quotas and Limit Ranges
### Governing Namespace Resource Usage
**Intermediate Kubernetes — Resource Governance (companion to Module 2)**

---

## Lab Overview

### What You Will Do

- Create a **ResourceQuota** that caps a namespace's aggregate CPU/memory and object counts
- See how a quota **forces every Pod to declare requests/limits**
- Use a **LimitRange** to supply **defaults** and enforce per-container **min/max**
- Watch quota usage grow and hit the ceiling with a Deployment that can't fully scale

### Why this matters

On a shared cluster, one team's runaway workload can starve everyone else. **ResourceQuota** caps what a namespace may consume in aggregate; **LimitRange** sets per-container defaults and bounds. Together they are the core of multi-tenant resource governance.

> **Note on the namespace:** this lab uses a `quota-<usernumber>` namespace on purpose. On this platform, namespaces named `lab-*` (and similar) automatically receive a `student-quota` + `student-limits` via a Kyverno policy — great for guardrails, but it would hide the cause-and-effect you're about to see. The `quota-*` namespace is *not* auto-governed, so you create everything yourself.

### Prerequisites

- Completion of Lab 1 with `kubectl` and cluster access configured

### Duration

Approximately 25-35 minutes

---

## Environment Setup

```bash
cd ~/environment/custom_k8s/labs/lab-02-quota
export STUDENT_NAME=<usernumber>
echo "Student: $STUDENT_NAME"
kubectl create namespace quota-$STUDENT_NAME
kubectl config set-context --current --namespace=quota-$STUDENT_NAME
```

---

## Step 1: Create a ResourceQuota

```bash
envsubst '$STUDENT_NAME' < resource-quota.yaml | kubectl apply -f -

# USED vs HARD for every constrained resource
kubectl describe resourcequota team-quota -n quota-$STUDENT_NAME
```

> ✅ **Checkpoint:** `describe` shows a table of `Used` vs `Hard` — `requests.cpu 0/1`, `requests.memory 0/1Gi`, `pods 0/10`, etc. Nothing is consuming the quota yet.

---

## Step 2: The Quota Forces Requests

Once a namespace has a quota on `requests.cpu`/`requests.memory`, **every** container must declare those requests — Kubernetes can't count what you don't declare. Try a Pod with **no** resources:

```bash
envsubst '$STUDENT_NAME' < unbounded-pod.yaml | kubectl apply -f -
```

> ⚠️ **Result:** the Pod is **rejected** — `Error ... forbidden: failed quota: team-quota: must specify limits.cpu, limits.memory, requests.cpu, requests.memory`. The quota won't admit a Pod it can't account for.

---

## Step 3: LimitRange Supplies Defaults

Rather than force every developer to hand-write requests, a **LimitRange** provides namespace **defaults** (and enforces min/max):

```bash
envsubst '$STUDENT_NAME' < limit-range.yaml | kubectl apply -f -
kubectl describe limitrange default-limits -n quota-$STUDENT_NAME

# The SAME Pod that was rejected now succeeds
envsubst '$STUDENT_NAME' < unbounded-pod.yaml | kubectl apply -f -

kubectl get pod no-resources -n quota-$STUDENT_NAME \
  -o jsonpath='requests={.spec.containers[0].resources.requests} limits={.spec.containers[0].resources.limits}{"\n"}'
```

> ✅ **Checkpoint:** The Pod is now **admitted**, and even though the manifest set no resources, it has `requests={cpu:100m, memory:128Mi}` and `limits={cpu:500m, memory:256Mi}` — the LimitRange's defaults. Re-check the quota: `requests.cpu` is now `100m/1`.

---

## Step 4: Hit the Ceiling

A quota also caps **aggregate** usage. This Deployment wants 3 replicas at 400m CPU each (1200m), but the quota allows only 1000m:

```bash
envsubst '$STUDENT_NAME' < bounded-deployment.yaml | kubectl apply -f -
sleep 8

kubectl get deployment web -n quota-$STUDENT_NAME
kubectl get replicaset -n quota-$STUDENT_NAME
kubectl describe resourcequota team-quota -n quota-$STUDENT_NAME | grep -E 'requests.cpu|pods'
```

Find the quota rejection in the ReplicaSet's events:

```bash
kubectl describe replicaset -n quota-$STUDENT_NAME | grep -i "exceeded quota" | head -1
```

> ✅ **Checkpoint:** The Deployment is stuck **below** 3 ready replicas (e.g. `2/3`) — the replica that would push `requests.cpu` over `1` is rejected with **`exceeded quota: team-quota`**. Quotas apply to the *sum* across the namespace, so a Deployment simply can't scale past them.

---

## Step 5: Clean Up

```bash
kubectl delete namespace quota-$STUDENT_NAME
```

---

## Summary

- A **ResourceQuota** caps a namespace's **aggregate** requests/limits and object counts (`Used` vs `Hard`).
- A quota on compute **requires** every container to declare requests/limits — otherwise the Pod is rejected.
- A **LimitRange** supplies per-container **defaults** (so undeclared Pods are admitted) and enforces **min/max** bounds.
- Aggregate quotas cap scaling: a Deployment stops at the replica count that fits, and the ReplicaSet reports **`exceeded quota`**.
- Together, ResourceQuota + LimitRange are the foundation of **multi-tenant** resource governance.
