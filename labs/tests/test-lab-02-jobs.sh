#!/bin/bash
###############################################################################
# Lab 2 (Part 3) Test: Jobs and CronJobs
# Covers: run-to-completion Job, parallel Job (completions/parallelism),
#         CronJob (schedule + concurrencyPolicy), on-demand trigger, suspend.
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAB_DIR="$(cd "$SCRIPT_DIR/../lab-02-jobs" && pwd)"
source "$SCRIPT_DIR/lib.sh"

export STUDENT_NAME="test-$$"
NS="lab-jobs-$STUDENT_NAME"
echo "=== Lab 2 (Part 3): Jobs and CronJobs (ns: $NS) ==="
echo ""

kubectl create namespace "$NS" &>/dev/null

# ─── Step 1: Basic Job ─────────────────────────────────────────────────────

echo "Step 1: Basic Job"

envsubst '$STUDENT_NAME' < "$LAB_DIR/job.yaml" | kubectl apply -f - &>/dev/null
kubectl wait --for=condition=Complete job/batch-hello -n "$NS" --timeout=120s &>/dev/null

JOB_OK=$(kubectl get job batch-hello -n "$NS" \
  -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null)
assert_eq "Job reaches Complete condition" "True" "$JOB_OK"

JOB_SUCCEEDED=$(kubectl get job batch-hello -n "$NS" -o jsonpath='{.status.succeeded}' 2>/dev/null)
assert_eq "Job has 1 succeeded Pod" "1" "$JOB_SUCCEEDED"

JOB_LOG=$(kubectl logs job/batch-hello -n "$NS" 2>/dev/null)
assert_contains "Job ran to completion (log)" "$JOB_LOG" "Job complete"

# ─── Step 2: Parallel Job ──────────────────────────────────────────────────

echo ""
echo "Step 2: Parallel Job"

envsubst '$STUDENT_NAME' < "$LAB_DIR/parallel-job.yaml" | kubectl apply -f - &>/dev/null

P_COMPLETIONS=$(kubectl get job batch-parallel -n "$NS" -o jsonpath='{.spec.completions}' 2>/dev/null)
assert_eq "parallel Job requests 6 completions" "6" "$P_COMPLETIONS"
P_PARALLELISM=$(kubectl get job batch-parallel -n "$NS" -o jsonpath='{.spec.parallelism}' 2>/dev/null)
assert_eq "parallel Job runs 3 at a time" "3" "$P_PARALLELISM"

kubectl wait --for=condition=Complete job/batch-parallel -n "$NS" --timeout=180s &>/dev/null
P_SUCCEEDED=$(kubectl get job batch-parallel -n "$NS" -o jsonpath='{.status.succeeded}' 2>/dev/null)
assert_eq "parallel Job reaches 6 successful completions" "6" "$P_SUCCEEDED"

# ─── Step 3: CronJob ───────────────────────────────────────────────────────

echo ""
echo "Step 3: CronJob"

envsubst '$STUDENT_NAME' < "$LAB_DIR/cronjob.yaml" | kubectl apply -f - &>/dev/null

assert_cmd "CronJob created" kubectl get cronjob hello-cron -n "$NS"

CRON_SCHED=$(kubectl get cronjob hello-cron -n "$NS" -o jsonpath='{.spec.schedule}' 2>/dev/null)
assert_eq "CronJob has an every-minute schedule" "*/1 * * * *" "$CRON_SCHED"

CRON_CONC=$(kubectl get cronjob hello-cron -n "$NS" -o jsonpath='{.spec.concurrencyPolicy}' 2>/dev/null)
assert_eq "CronJob concurrencyPolicy is Forbid" "Forbid" "$CRON_CONC"

# Trigger on demand (don't wait for the schedule) and verify the Job template runs.
kubectl create job --from=cronjob/hello-cron manual-run -n "$NS" &>/dev/null
kubectl wait --for=condition=Complete job/manual-run -n "$NS" --timeout=90s &>/dev/null
MANUAL_LOG=$(kubectl logs job/manual-run -n "$NS" 2>/dev/null)
assert_contains "on-demand CronJob trigger runs the template" "$MANUAL_LOG" "Hello from the scheduled job"

# Suspend the schedule.
kubectl patch cronjob hello-cron -n "$NS" -p '{"spec":{"suspend":true}}' &>/dev/null
CRON_SUSPEND=$(kubectl get cronjob hello-cron -n "$NS" -o jsonpath='{.spec.suspend}' 2>/dev/null)
assert_eq "CronJob can be suspended" "true" "$CRON_SUSPEND"

# ─── Cleanup ──────────────────────────────────────────────────────────────

cleanup_ns "$NS"
summary
