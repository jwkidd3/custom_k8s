# Lab 2 (Part 3): Jobs and CronJobs
### Run-to-Completion, Parallelism, and Scheduled Workloads
**Intermediate Kubernetes — Batch Workloads (companion to Module 2)**

---

## Lab Overview

### What You Will Do

- Run a **Job** that executes a task to completion
- Run a **parallel Job** with `completions` and `parallelism`
- Schedule recurring work with a **CronJob**
- Trigger a CronJob **on demand** and **suspend** it

### Why this matters

Not every workload is a long-running server. Batch processing, data migrations, report generation, backups, and cleanup tasks all *start, do work, and finish*. **Jobs** run a Pod to completion (with retries); **CronJobs** run Jobs on a schedule. Both are first-class `batch/v1` workloads.

### Prerequisites

- Completion of Lab 1 with `kubectl` and cluster access configured

### Duration

Approximately 25-35 minutes

---

## Environment Setup

```bash
cd ~/environment/custom_k8s/labs/lab-02-jobs
export STUDENT_NAME=<usernumber>
echo "Student: $STUDENT_NAME"
kubectl create namespace lab-jobs-$STUDENT_NAME
kubectl config set-context --current --namespace=lab-jobs-$STUDENT_NAME
```

---

## Step 1: A Basic Job

A **Job** creates one or more Pods and ensures a specified number of them **successfully complete**. Unlike a Deployment, a Job's Pod is *meant to exit* — so `restartPolicy` is `Never` or `OnFailure`, never `Always`.

```bash
envsubst '$STUDENT_NAME' < job.yaml | kubectl apply -f -

# Watch it run and complete (COMPLETIONS goes 0/1 -> 1/1)
kubectl get job batch-hello -n lab-jobs-$STUDENT_NAME -w
```

Once it's `1/1`, inspect it:

```bash
# Wait for the Complete condition, then read the results
kubectl wait --for=condition=Complete job/batch-hello -n lab-jobs-$STUDENT_NAME --timeout=90s

kubectl get job batch-hello -n lab-jobs-$STUDENT_NAME
kubectl logs job/batch-hello -n lab-jobs-$STUDENT_NAME
```

> ✅ **Checkpoint:** The Job shows `COMPLETIONS 1/1`, its status `succeeded` count is **1**, and the logs end with **"Job complete"**. `backoffLimit: 4` means a failing Pod would be retried up to 4 times before the Job is marked failed.

---

## Step 2: Parallel Jobs

A Job can run many Pods. `completions` is how many successful runs you need; `parallelism` is how many run **at once**. Here we want **6** completions, **3** at a time:

```bash
envsubst '$STUDENT_NAME' < parallel-job.yaml | kubectl apply -f -

# Watch pods appear 3 at a time until 6 have completed
kubectl get pods -n lab-jobs-$STUDENT_NAME -l job-name=batch-parallel -w
```

```bash
kubectl wait --for=condition=Complete job/batch-parallel -n lab-jobs-$STUDENT_NAME --timeout=120s
kubectl get job batch-parallel -n lab-jobs-$STUDENT_NAME \
  -o custom-columns='NAME:.metadata.name,COMPLETIONS:.spec.completions,PARALLELISM:.spec.parallelism,SUCCEEDED:.status.succeeded'
```

> ✅ **Checkpoint:** You see Pods start in waves of **3**, and the Job finishes with **`SUCCEEDED 6`**. This is the fan-out pattern for batch work — split it into N units and run P at a time.

---

## Step 3: CronJobs

A **CronJob** creates a Job on a **schedule** (standard cron syntax). This one runs every minute:

```bash
envsubst '$STUDENT_NAME' < cronjob.yaml | kubectl apply -f -

kubectl get cronjob hello-cron -n lab-jobs-$STUDENT_NAME
```

Wait for the next minute boundary, then look at the Jobs it created:

```bash
# After ~1 minute, a Job appears with a timestamped name
kubectl get jobs -n lab-jobs-$STUDENT_NAME
kubectl logs -l app -n lab-jobs-$STUDENT_NAME --tail=5 2>/dev/null \
  || kubectl logs job/$(kubectl get jobs -n lab-jobs-$STUDENT_NAME \
       -o jsonpath='{.items[0].metadata.name}') -n lab-jobs-$STUDENT_NAME
```

> ✅ **Checkpoint:** After a minute, `kubectl get jobs` shows a Job named `hello-cron-<timestamp>`, and its logs print **"Hello from the scheduled job"**. `concurrencyPolicy: Forbid` skips a run if the previous one is still going; `successfulJobsHistoryLimit` caps how many finished Jobs are kept.

### Trigger on demand and suspend

You don't have to wait for the schedule — create a Job **from** the CronJob immediately, and **suspend** the schedule when you don't want it firing:

```bash
# Run it now (great for testing a CronJob's Job template)
kubectl create job --from=cronjob/hello-cron manual-run -n lab-jobs-$STUDENT_NAME
kubectl wait --for=condition=Complete job/manual-run -n lab-jobs-$STUDENT_NAME --timeout=90s
kubectl logs job/manual-run -n lab-jobs-$STUDENT_NAME

# Pause the schedule (no new Jobs until resumed)
kubectl patch cronjob hello-cron -n lab-jobs-$STUDENT_NAME -p '{"spec":{"suspend":true}}'
kubectl get cronjob hello-cron -n lab-jobs-$STUDENT_NAME
```

> ✅ **Checkpoint:** `manual-run` completes immediately with the same output, and after patching, the CronJob's `SUSPEND` column reads **`True`** — no further Jobs are scheduled until you set it back to `false`.

---

## Step 4: Clean Up

```bash
kubectl delete namespace lab-jobs-$STUDENT_NAME
```

---

## Summary

- A **Job** runs a Pod **to completion** with retries (`backoffLimit`); use `restartPolicy: Never`/`OnFailure`.
- **`completions`** sets how many successes are needed; **`parallelism`** sets how many run concurrently.
- A **CronJob** creates Jobs on a cron **schedule**, with `concurrencyPolicy` and history limits to control overlap and retention.
- **`kubectl create job --from=cronjob/<name>`** runs a CronJob's template on demand; **`suspend: true`** pauses the schedule.
- **`ttlSecondsAfterFinished`** auto-cleans finished Jobs so they don't pile up.
