#!/bin/bash
###############################################################################
# Lab 2 (Part 4) Test: Resource Quotas and Limit Ranges
# Covers: ResourceQuota forces requests (rejects unbounded Pod), LimitRange
#         supplies defaults (admits it), aggregate quota caps a Deployment.
# NOTE: uses a quota-* namespace so the platform's Kyverno generate-resource-quota
#       policy (which targets lab-*/obs-*/etc.) does NOT auto-create a quota here.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-02-quota" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS="quota-$STUDENT_NAME"
echo "=== Lab 2 (Part 4): Resource Quotas and Limit Ranges (ns: $NS) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null
# Guard: confirm nothing auto-generated a quota/limitrange here (clean baseline).
sleep 2
AUTO_RQ=$(kubectl get resourcequota -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d ' ')
assert_eq "namespace starts with no auto-generated quota" "0" "$AUTO_RQ"

# ─── Step 1: ResourceQuota ─────────────────────────────────────────────────

echo ""
echo "Step 1: ResourceQuota"

envsubst '$STUDENT_NAME' < "$LAB_DIR/resource-quota.yaml" | kubectl apply -f - &>/dev/null
assert_cmd "ResourceQuota created" kubectl get resourcequota team-quota -n "$NS"

HARD_CPU=$(kubectl get resourcequota team-quota -n "$NS" -o jsonpath='{.status.hard.requests\.cpu}' 2>/dev/null)
assert_eq "quota hard requests.cpu is 1" "1" "$HARD_CPU"
HARD_PODS=$(kubectl get resourcequota team-quota -n "$NS" -o jsonpath='{.status.hard.pods}' 2>/dev/null)
assert_eq "quota hard pods is 10" "10" "$HARD_PODS"

# ─── Step 2: quota forces requests (unbounded Pod rejected) ─────────────────

echo ""
echo "Step 2: Quota forces requests"

REJECT=$(envsubst '$STUDENT_NAME' < "$LAB_DIR/unbounded-pod.yaml" | kubectl apply -f - 2>&1)
if echo "$REJECT" | grep -qiE 'forbidden|must specify|exceeded quota'; then
  pass "Pod with no requests is rejected under the quota"
else
  fail "unbounded Pod should be rejected (got: $(echo "$REJECT" | head -1))"
fi

# ─── Step 3: LimitRange supplies defaults (Pod admitted) ────────────────────

echo ""
echo "Step 3: LimitRange defaults"

envsubst '$STUDENT_NAME' < "$LAB_DIR/limit-range.yaml" | kubectl apply -f - &>/dev/null
assert_cmd "LimitRange created" kubectl get limitrange default-limits -n "$NS"

envsubst '$STUDENT_NAME' < "$LAB_DIR/unbounded-pod.yaml" | kubectl apply -f - &>/dev/null
sleep 2
assert_cmd "same Pod is now admitted" kubectl get pod no-resources -n "$NS"

DEF_REQ_CPU=$(kubectl get pod no-resources -n "$NS" \
  -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
assert_eq "LimitRange injected default request cpu (100m)" "100m" "$DEF_REQ_CPU"
DEF_LIM_MEM=$(kubectl get pod no-resources -n "$NS" \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null)
assert_eq "LimitRange injected default limit memory (256Mi)" "256Mi" "$DEF_LIM_MEM"

# ─── Step 4: aggregate quota caps a Deployment ─────────────────────────────

echo ""
echo "Step 4: Aggregate quota caps scaling"

envsubst '$STUDENT_NAME' < "$LAB_DIR/bounded-deployment.yaml" | kubectl apply -f - &>/dev/null
sleep 10

READY=$(kubectl get deployment web -n "$NS" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
READY=${READY:-0}
if [ "$READY" -lt 3 ]; then
  pass "Deployment is capped below 3 replicas by the quota (ready=$READY)"
else
  fail "Deployment should be quota-capped below 3 (ready=$READY)"
fi

EXCEEDED=$(kubectl describe replicaset -n "$NS" 2>/dev/null | grep -ci "exceeded quota")
if [ "$EXCEEDED" -gt 0 ]; then
  pass "ReplicaSet reports 'exceeded quota'"
else
  fail "expected an 'exceeded quota' event on the ReplicaSet"
fi

# ─── Cleanup ──────────────────────────────────────────────────────────────

cleanup_ns "$NS"
summary
