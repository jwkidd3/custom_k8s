# Lab 13 (Part 2): Custom Resource Definitions (CRDs)
### Extending the Kubernetes API with Your Own Resource Types
**Intermediate Kubernetes — Extending Kubernetes (companion to Module 13)**

---

## Lab Overview

### What You Will Do

- Register a **CustomResourceDefinition** that adds a new `Website` resource type
- Create and manage **custom resources** with `kubectl`, just like built-in objects
- Enforce structure with an **OpenAPI validation schema**
- Discover your type via `kubectl api-resources`, `kubectl explain`, and printer columns
- See how **controllers/operators** turn custom resources into real behavior

### Why this matters

Almost every tool you've used in this course — Flux (`HelmRelease`), cert-manager (`Certificate`), Gateway API (`HTTPRoute`), Kyverno (`ClusterPolicy`) — extends Kubernetes through **CRDs**. A CRD teaches the API server a new `kind`; a **controller** then watches those objects and makes the cluster match them. This lab covers the first half (the CRD + custom resources); the operator pattern is the second half.

> **Note:** A CRD is **cluster-scoped**, so this lab gives each student their own API **group** (`<usernumber>.example.com`) to avoid collisions. Set `STUDENT_NAME` and the commands below resolve to your group.

### Prerequisites

- Completion of Lab 1 with `kubectl` and cluster access configured

### Duration

Approximately 25-35 minutes

---

## Environment Setup

```bash
cd ~/environment/custom_k8s/labs/lab-13-crds
export STUDENT_NAME=<usernumber>
export GROUP=$STUDENT_NAME.example.com    # your personal API group
echo "Student: $STUDENT_NAME  Group: $GROUP"
kubectl create namespace crd-$STUDENT_NAME
```

---

## Step 1: Register a CustomResourceDefinition

The CRD tells the API server about a new `kind: Website` in your group, with a validation schema and extra columns for `kubectl get`:

```bash
envsubst '$STUDENT_NAME' < website-crd.yaml | kubectl apply -f -

# Wait until the API server has wired it up
kubectl wait --for=condition=Established crd/websites.$GROUP --timeout=30s

# Your new type now shows up alongside built-in resources
kubectl api-resources --api-group=$GROUP
```

> ✅ **Checkpoint:** The CRD reports `Established`, and `api-resources` lists `websites` (shortname `ws`, kind `Website`, namespaced). You just extended the Kubernetes API — no server restart, no recompile.

---

## Step 2: Create Custom Resources

A **custom resource** is an instance of your new type. Create one and manage it exactly like a Pod or Deployment:

```bash
envsubst '$STUDENT_NAME' < website-example.yaml | kubectl apply -f -

# Your additionalPrinterColumns render here
kubectl get websites.$GROUP -n crd-$STUDENT_NAME
kubectl describe website.$GROUP blog -n crd-$STUDENT_NAME

# Standard verbs, labels, YAML output all work
kubectl get ws -n crd-$STUDENT_NAME -o yaml
```

> ✅ **Checkpoint:** `kubectl get` shows your `blog` Website with `DOMAIN`, `REPLICAS`, and `THEME` columns. It's stored in etcd and served by the API server like any native object — but nothing *acts* on it yet (see Step 5).

---

## Step 3: Schema Validation

The OpenAPI schema in the CRD makes the API server reject malformed resources. Try an invalid one:

```bash
envsubst '$STUDENT_NAME' < website-invalid.yaml | kubectl apply -f -
```

> ⚠️ **Result:** rejected before it's ever stored — e.g. `spec.replicas: Invalid value: 99: spec.replicas in body should be less than or equal to 10`. The schema also requires `domain` and restricts `theme` to `light`/`dark`. Structural schemas give your custom type the same guardrails built-in types enjoy.

---

## Step 4: Discover the Type

Because the schema lives in the API server, your type is **self-documenting**:

```bash
# Explain fields like any built-in resource
kubectl explain website.spec --api-version=$GROUP/v1

# Short name works too
kubectl get ws -n crd-$STUDENT_NAME
```

> ✅ **Checkpoint:** `kubectl explain` prints your fields (`domain`, `replicas`, `theme`) with their types and which are required — generated straight from the CRD schema.

---

## Step 5: The Other Half — Controllers

Your `Website` is just **data** right now. Creating one didn't start any Pods, because a CRD only defines a *type* — it doesn't *do* anything. The magic comes from a **controller** (an **operator**) that:

1. **Watches** for `Website` objects,
2. **Reconciles** reality toward the spec (e.g. create a Deployment + Service for `blog.example.com` with 3 replicas),
3. **Reports** back through the resource's `status`.

You've already used operators built exactly this way:

| CRD | Controller does... |
|-----|--------------------|
| Flux `HelmRelease` | installs/upgrades a Helm chart |
| cert-manager `Certificate` | issues & renews TLS certs |
| Gateway API `HTTPRoute` | programs the Envoy Gateway |

> This lab builds the **CRD** (the API); writing the **controller** is the operator pattern, a topic of its own.

---

## Step 6: Clean Up

```bash
# Deleting the CRD cascade-deletes every Website in it
kubectl delete crd websites.$GROUP
kubectl delete namespace crd-$STUDENT_NAME
```

---

## Summary

- A **CRD** teaches the API server a new `kind` — extending Kubernetes with no restart or recompile.
- **Custom resources** are managed with the same `kubectl` verbs, labels, and output formats as built-in objects.
- An **OpenAPI validation schema** enforces required fields, types, ranges, and enums; **additionalPrinterColumns** enrich `kubectl get`; **shortNames** and `kubectl explain` make the type discoverable.
- A CRD is only the **API**; a **controller/operator** watches custom resources and reconciles the cluster to match — that's how Flux, cert-manager, and Gateway API all work.
- CRDs are **cluster-scoped**; isolate them (here, per-student groups) to avoid collisions.
