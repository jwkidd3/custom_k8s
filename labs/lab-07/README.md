# Lab 7: RBAC and Pod Security
### Roles, Bindings, Pod Security Standards, and SecurityContexts
**Intermediate Kubernetes — Module 7 of 13**

---

## Lab Overview

### Objectives

- Explore existing ClusterRoles and bindings
- Create Roles, RoleBindings, and ServiceAccounts
- Apply Pod Security Standards and SecurityContexts
- Test RBAC permission boundaries

### Prerequisites

- Completion of Lab 1 with `kubectl` and cluster access configured
- kubectl with cluster-admin access on a running EKS cluster

> **Duration:** ~45-55 minutes

---

## Environment Setup

```bash
cd ~/environment/custom_k8s/labs/lab-07
export STUDENT_NAME=<usernumber>
echo "Student: $STUDENT_NAME"
kubectl config set-context --current --namespace=default
```

---

## Step 1: Explore Existing ClusterRoles

Create a namespace and examine the built-in ClusterRoles:

```bash
kubectl create namespace lab07-$STUDENT_NAME

kubectl get clusterroles | head -20

# Examine key built-in ClusterRoles
kubectl describe clusterrole admin
kubectl describe clusterrole edit
kubectl describe clusterrole view
```

---

## Step 2: Create a Namespace-Scoped Role and Bind It

Create a Role that allows read-only access to pods:

<!-- Creates a Role granting get/list/watch on pods and pods/log -->

Apply the manifest and create a ServiceAccount:

```bash
envsubst '$STUDENT_NAME' < pod-reader-role.yaml | kubectl apply -f -
kubectl create serviceaccount pod-viewer -n lab07-$STUDENT_NAME
```

<!-- Creates a RoleBinding connecting the pod-viewer SA to the pod-reader Role -->

Apply the manifest:

```bash
envsubst '$STUDENT_NAME' < pod-reader-binding.yaml | kubectl apply -f -
```

---

## Step 3: Test Permissions with kubectl auth can-i

```bash
kubectl auth can-i --list -n lab07-$STUDENT_NAME \
  --as=system:serviceaccount:lab07-$STUDENT_NAME:pod-viewer
```

> ✅ **Checkpoint:** Output shows `get`, `list`, `watch` on `pods` and `get` on `pods/log` -- nothing else.

---

## Step 4: Deploy a Pod Using the ServiceAccount

<!-- Creates a pod running kubectl with the pod-viewer ServiceAccount -->

Apply the manifest:

```bash
envsubst '$STUDENT_NAME' < rbac-test-pod.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready pod/rbac-test -n lab07-$STUDENT_NAME --timeout=60s

# This should SUCCEED
kubectl exec rbac-test -n lab07-$STUDENT_NAME -- kubectl get pods -n lab07-$STUDENT_NAME

# This should FAIL with Forbidden
kubectl exec rbac-test -n lab07-$STUDENT_NAME -- kubectl create deployment \
  test --image=nginx -n lab07-$STUDENT_NAME
```

> ✅ **Checkpoint:** `get pods` succeeds; `create deployment` fails with Forbidden.

---

## Step 5: Create a ClusterRole for Cross-Namespace Access

<!-- Creates a ClusterRole granting read access to pods, services, deployments, and replicasets -->

Apply the manifest and create a ServiceAccount:

```bash
envsubst '$STUDENT_NAME' < cluster-reader-role.yaml | kubectl apply -f -
kubectl create serviceaccount cluster-viewer -n lab07-$STUDENT_NAME
```

Bind it with a ClusterRoleBinding:

<!-- Creates a ClusterRoleBinding connecting the cluster-viewer SA to the ClusterRole -->

Apply the manifest:

```bash
envsubst '$STUDENT_NAME' < cluster-reader-binding.yaml | kubectl apply -f -

# Test cross-namespace read (should be YES)
kubectl auth can-i list pods -n kube-system \
  --as=system:serviceaccount:lab07-$STUDENT_NAME:cluster-viewer

# Test delete (should be NO)
kubectl auth can-i delete pods -n kube-system \
  --as=system:serviceaccount:lab07-$STUDENT_NAME:cluster-viewer
```

> ✅ **Checkpoint:** `list pods` returns `yes` in any namespace; `delete pods` returns `no`.

---

## Step 6: Apply Pod Security Standards

Create a namespace with the **restricted** Pod Security Standard:

```bash
kubectl create namespace lab07-restricted-$STUDENT_NAME

kubectl label namespace lab07-restricted-$STUDENT_NAME \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest
```

---

## Step 7: Test Pod Security -- Violations

Try deploying pods that violate the restricted profile:

<!-- Creates a pod with privileged: true (should be rejected) -->

<!-- Creates a pod running as root user (should be rejected) -->

Apply both manifests:

```bash
# Both should FAIL under the restricted profile
envsubst '$STUDENT_NAME' < privileged-pod.yaml | kubectl apply -f -
envsubst '$STUDENT_NAME' < root-pod.yaml | kubectl apply -f -
```

> ✅ **Checkpoint:** Both pods are blocked. The privileged pod is rejected by two independent admission layers — expect a Pod Security error (`violates PodSecurity "restricted:latest"`) or the cluster Kyverno policy message (`Privileged containers are not allowed.`). The root pod fails the `runAsNonRoot` check. Either message means the guardrails are working.

---

## Step 8: Deploy a Compliant Secure Pod

<!-- Creates a pod that meets the restricted security profile (non-root, read-only FS, no capabilities) -->

Apply the manifest:

```bash
envsubst '$STUDENT_NAME' < secure-pod.yaml | kubectl apply -f -
kubectl wait --for=condition=Ready pod/secure-app \
  -n lab07-restricted-$STUDENT_NAME --timeout=60s

# Verify security settings inside the pod
kubectl exec secure-app -n lab07-restricted-$STUDENT_NAME -- id
kubectl exec secure-app -n lab07-restricted-$STUDENT_NAME -- touch /test-file
kubectl exec secure-app -n lab07-restricted-$STUDENT_NAME -- touch /tmp/test-file
kubectl exec secure-app -n lab07-restricted-$STUDENT_NAME -- \
  cat /proc/1/status | grep -i cap
```

> ✅ **Checkpoint:**
> - `id` --> `uid=1000 gid=1000 groups=1000`
> - `touch /test-file` --> **Read-only file system** error
> - `touch /tmp/test-file` --> succeeds
> - `CapEff` --> `0000000000000000` (no capabilities)

---

---

## Step 9: Clean Up

```bash
kubectl delete clusterrolebinding cluster-pod-reader-binding-$STUDENT_NAME
kubectl delete clusterrole cluster-pod-reader-$STUDENT_NAME

kubectl delete namespace lab07-$STUDENT_NAME
kubectl delete namespace lab07-restricted-$STUDENT_NAME
```

---

## Summary

- RBAC uses an additive model -- permissions are granted, never denied
- Roles are namespace-scoped; ClusterRoles are cluster-scoped; bind them with RoleBindings or ClusterRoleBindings
- Pod Security Standards (restricted, baseline, privileged) enforce security profiles at the namespace level
- SecurityContext settings (`runAsNonRoot`, `readOnlyRootFilesystem`, `drop: ALL`) provide defense-in-depth

---

*Lab 7 Complete — Up Next: Lab 8 — Network Policies*
