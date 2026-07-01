#!/bin/bash
###############################################################################
# Lab 1 (Part 2) Test: Init Containers & Multi-Container Pods
# Covers: init container ordered setup, sidecar (shared volume + concurrency),
#         native sidecar (initContainer restartPolicy: Always), per-container logs.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-01-pods" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS="lab-pods-$STUDENT_NAME"
echo "=== Lab 1 (Part 2): Init Containers & Multi-Container Pods (ns: $NS) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null

# ─── Step 1: Init container — ordered setup ────────────────────────────────

echo "Step 1: Init Container"

envsubst '$STUDENT_NAME' < "$LAB_DIR/init-container-pod.yaml" | kubectl apply -f - &>/dev/null
wait_for_pod "$NS" init-demo 90

INIT_REASON=$(kubectl get pod init-demo -n "$NS" \
  -o jsonpath='{.status.initContainerStatuses[0].state.terminated.reason}' 2>/dev/null)
assert_eq "init container ran to completion" "Completed" "$INIT_REASON"

INIT_LOG=$(kubectl logs init-demo -n "$NS" -c setup 2>/dev/null)
assert_contains "init container logged completion" "$INIT_LOG" "init container finished"

INIT_BODY=$(kubectl exec init-demo -n "$NS" -c web -- curl -s --max-time 5 localhost:80 2>/dev/null)
assert_contains "app serves content prepared by the init container" "$INIT_BODY" "init container"

# ─── Step 2: Multi-container Pod — sidecar ─────────────────────────────────

echo ""
echo "Step 2: Sidecar (multi-container Pod)"

envsubst '$STUDENT_NAME' < "$LAB_DIR/sidecar-pod.yaml" | kubectl apply -f - &>/dev/null
wait_for_pod "$NS" sidecar-demo 90

C_COUNT=$(kubectl get pod sidecar-demo -n "$NS" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null | wc -w | tr -d ' ')
assert_eq "sidecar Pod has 2 containers" "2" "$C_COUNT"

READY=$(kubectl get pod sidecar-demo -n "$NS" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
assert_eq "both containers are Ready" "true true" "$READY"

SIDE_BODY=$(kubectl exec sidecar-demo -n "$NS" -c web -- curl -s --max-time 5 localhost:80 2>/dev/null)
assert_contains "web serves content written by the sidecar (shared volume)" "$SIDE_BODY" "refreshed by the sidecar"

SIDE_LOG=$(kubectl logs sidecar-demo -n "$NS" -c content-sync --tail=5 2>/dev/null)
assert_contains "per-container logs work (-c content-sync)" "$SIDE_LOG" "content-sync: refreshed"

# ─── Step 3: Native sidecar (restartPolicy: Always init container) ──────────

echo ""
echo "Step 3: Native Sidecar"

envsubst '$STUDENT_NAME' < "$LAB_DIR/native-sidecar-pod.yaml" | kubectl apply -f - &>/dev/null
wait_for_pod "$NS" native-sidecar-demo 90

NS_RP=$(kubectl get pod native-sidecar-demo -n "$NS" \
  -o jsonpath='{.spec.initContainers[0].restartPolicy}' 2>/dev/null)
assert_eq "native sidecar is an initContainer with restartPolicy: Always" "Always" "$NS_RP"

# Give the app a few cycles to write log lines the sidecar forwards.
SHIP_LOG=""
for _i in $(seq 1 6); do
  SHIP_LOG=$(kubectl logs native-sidecar-demo -n "$NS" -c log-shipper 2>/dev/null)
  echo "$SHIP_LOG" | grep -q "app event" && break
  sleep 4
done
assert_contains "native sidecar streams the app's log (app event lines)" "$SHIP_LOG" "app event"

# ─── Cleanup ──────────────────────────────────────────────────────────────

cleanup_ns "$NS"
summary
