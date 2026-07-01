#!/bin/bash
###############################################################################
# Lab 5 (Part 2) Test: Custom Resource Definitions (CRDs)
# Covers: register a CRD, create a custom resource, printer columns, OpenAPI
#         schema validation (invalid CR rejected), discovery via api-resources.
# NOTE: a CRD is cluster-scoped — this test uses a per-run API group and deletes
#       the CRD explicitly (cleanup_ns only handles the namespace).
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-05-crds" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
GROUP="$STUDENT_NAME.example.com"
NS="crd-$STUDENT_NAME"
CRD="websites.$GROUP"
echo "=== Lab 5 (Part 2): CRDs (ns: $NS, group: $GROUP) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null

# ─── Step 1: Register the CRD ──────────────────────────────────────────────

echo "Step 1: Register the CRD"

envsubst '$STUDENT_NAME' < "$LAB_DIR/website-crd.yaml" | kubectl apply -f - &>/dev/null
kubectl wait --for=condition=Established "crd/$CRD" --timeout=30s &>/dev/null

ESTABLISHED=$(kubectl get crd "$CRD" \
  -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null)
assert_eq "CRD reaches Established" "True" "$ESTABLISHED"

CRD_KIND=$(kubectl get crd "$CRD" -o jsonpath='{.spec.names.kind}' 2>/dev/null)
assert_eq "CRD registers kind Website" "Website" "$CRD_KIND"

API_KIND=$(kubectl api-resources --api-group="$GROUP" --no-headers 2>/dev/null | awk '{print $NF}' | head -1)
assert_eq "new type appears in api-resources" "Website" "$API_KIND"

# ─── Step 2: Create a custom resource ──────────────────────────────────────

echo ""
echo "Step 2: Create a custom resource"

envsubst '$STUDENT_NAME' < "$LAB_DIR/website-example.yaml" | kubectl apply -f - &>/dev/null
assert_cmd "custom resource 'blog' created" kubectl get "websites.$GROUP" blog -n "$NS"

CR_DOMAIN=$(kubectl get "websites.$GROUP" blog -n "$NS" -o jsonpath='{.spec.domain}' 2>/dev/null)
assert_eq "custom resource stores spec.domain" "blog.example.com" "$CR_DOMAIN"
CR_REPLICAS=$(kubectl get "websites.$GROUP" blog -n "$NS" -o jsonpath='{.spec.replicas}' 2>/dev/null)
assert_eq "custom resource stores spec.replicas" "3" "$CR_REPLICAS"

# Short name resolves to the same resource
assert_cmd "short name 'ws' resolves" kubectl get ws blog -n "$NS"

# ─── Step 3: Schema validation ─────────────────────────────────────────────

echo ""
echo "Step 3: Schema validation"

INVALID=$(envsubst '$STUDENT_NAME' < "$LAB_DIR/website-invalid.yaml" | kubectl apply -f - 2>&1)
if echo "$INVALID" | grep -qiE 'Invalid|required|should be less than'; then
  pass "invalid custom resource is rejected by the schema"
else
  fail "invalid CR should be rejected (got: $(echo "$INVALID" | head -1))"
fi

# ─── Cleanup ──────────────────────────────────────────────────────────────

# The CRD is cluster-scoped — delete it explicitly (this cascade-deletes CRs).
kubectl delete crd "$CRD" --ignore-not-found --wait=false &>/dev/null
cleanup_ns "$NS"
summary
