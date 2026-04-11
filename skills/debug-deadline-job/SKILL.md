---
name: debug-deadline-job
description: Debug AWS Deadline Cloud jobs — find farms, queues, search jobs, check status, fetch session logs, extract SSM mi- target IDs, and diagnose failing jobs. Use when debugging Deadline Cloud jobs, checking job status, reading job logs, or finding SSM connection targets.
---

## Overview

Step-by-step workflow for debugging AWS Deadline Cloud jobs using the AWS CLI. Each step shows the command, what it returns, and what to do next.

All commands use `--region us-west-2` by default. Adjust if the user's resources are in a different region.

## Step 1: List Farms

Find the farm ID. Most users have one farm.

```bash
aws deadline list-farms \
  --query 'farms[*].{id:farmId,name:displayName}' \
  --output table
```

Returns a table of farm IDs and display names. Use the `farmId` for all subsequent commands.

## Step 2: List Queues

Find the queue ID within a farm.

```bash
aws deadline list-queues \
  --farm-id <FARM_ID> \
  --query 'queues[*].{id:queueId,name:displayName}' \
  --output table
```

Returns queue IDs and names. Use the `queueId` for job queries.

## Step 3: Search Jobs

Find jobs by recency. The `search-jobs` API supports filtering and sorting.

```bash
aws deadline search-jobs \
  --farm-id <FARM_ID> \
  --queue-id <QUEUE_ID> \
  --item-offset 0 \
  --page-size 5 \
  --sort-expressions '[{"fieldSort":{"name":"CREATED_AT","sortOrder":"DESCENDING"}}]' \
  --query 'jobs[*].{id:jobId,name:name,status:taskRunStatus,created:createdAt}' \
  --output table
```

Key fields in the response:
- `jobId` — the job identifier (job-xxx)
- `name` — job display name
- `lifecycleStatus` — CREATE_COMPLETE, UPDATE_IN_PROGRESS, UPDATE_SUCCEEDED, etc.
- `taskRunStatus` — RUNNING, SUCCEEDED, FAILED, CANCELED, etc.
- `taskRunStatusCounts` — breakdown of task states
- `jobParameters` — all parameters passed at submission

To filter by status (e.g. only FAILED jobs):
```bash
aws deadline search-jobs \
  --farm-id <FARM_ID> \
  --queue-id <QUEUE_ID> \
  --item-offset 0 \
  --page-size 10 \
  --filter-expressions '{"filters":[{"stringFilter":{"name":"TASK_RUN_STATUS","operator":"EQUAL","value":"FAILED"}}],"operator":"AND"}' \
  --sort-expressions '[{"fieldSort":{"name":"CREATED_AT","sortOrder":"DESCENDING"}}]' \
  --query 'jobs[*].{id:jobId,name:name,status:taskRunStatus,created:createdAt}' \
  --output table
```

## Step 4: Get Job Details

Get full details for a specific job.

```bash
aws deadline get-job \
  --farm-id <FARM_ID> \
  --queue-id <QUEUE_ID> \
  --job-id <JOB_ID>
```

Key fields:
- `lifecycleStatus` / `lifecycleStatusMessage` — overall job state
- `taskRunStatus` / `taskRunStatusCounts` — per-task breakdown
- `parameters` — all job parameters (ActivationCode, ECR image, SessionMinutes, etc.)
- `startedAt` / `endedAt` — timing
- `maxRetriesPerTask` — retry config

## Step 5: List Sessions

Each job run creates one or more sessions on workers. Sessions contain the actual execution logs.

```bash
aws deadline list-sessions \
  --farm-id <FARM_ID> \
  --queue-id <QUEUE_ID> \
  --job-id <JOB_ID>
```

Returns an array of sessions with:
- `sessionId` — session-xxx identifier
- `fleetId` — which fleet ran it
- `workerId` — which worker ran it
- `lifecycleStatus` — STARTED, UPDATE_IN_PROGRESS, UPDATE_SUCCEEDED, ENDED
- `startedAt` / `endedAt` — timing

Use the `sessionId` to get logs.

## Step 6: Get Session Details (including log location)

```bash
aws deadline get-session \
  --farm-id <FARM_ID> \
  --queue-id <QUEUE_ID> \
  --job-id <JOB_ID> \
  --session-id <SESSION_ID>
```

Key fields:
- `log.options.logGroupName` — CloudWatch log group for the session
- `log.options.logStreamName` — CloudWatch log stream (same as sessionId)
- `workerLog.options.logGroupName` — worker agent log group
- `workerLog.options.logStreamName` — worker agent log stream
- `hostProperties.ec2InstanceType` — instance type (e.g. g6e.2xlarge)
- `hostProperties.hostName` — worker hostname
- `hostProperties.ipAddresses` — worker IP

The log group pattern is:
- Session logs: `/aws/deadline/<FARM_ID>/<QUEUE_ID>` with stream `<SESSION_ID>`
- Worker logs: `/aws/deadline/<FARM_ID>/<FLEET_ID>` with stream `<WORKER_ID>`

## Step 7: Fetch Session Logs

### Tail the last N log lines

```bash
aws logs get-log-events \
  --log-group-name "<LOG_GROUP>" \
  --log-stream-name "<SESSION_ID>" \
  --limit 50 \
  --query 'events[*].message' \
  --output text
```

Without `--start-from-head`, this returns the most recent lines (tail).

### Read logs from the beginning

```bash
aws logs get-log-events \
  --log-group-name "<LOG_GROUP>" \
  --log-stream-name "<SESSION_ID>" \
  --limit 100 \
  --start-from-head \
  --query 'events[*].message' \
  --output text
```

### Search logs for a pattern (e.g. SSM target, errors)

```bash
aws logs filter-log-events \
  --log-group-name "<LOG_GROUP>" \
  --log-stream-names "<SESSION_ID>" \
  --filter-pattern '"mi-"' \
  --query 'events[*].message' \
  --output text
```

Common filter patterns:
- `'"mi-"'` — find SSM managed node ID for port forwarding
- `'"ERROR"'` — find error messages
- `'"FAILED"'` — find failure messages
- `'"exit code"'` — find process exit codes
- `'"ComfyUI is ready"'` — confirm ComfyUI started
- `'"Render complete"'` — confirm render finished

## Step 8: Extract SSM Target and Connect

Once you find the `mi-XXXXXXX` ID from the logs, the user can connect:

Port forwarding (for ComfyUI GUI access):
```bash
aws ssm start-session \
  --target <MI_ID> \
  --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8188"],"localPortNumber":["8188"]}'
```

Interactive shell (for debugging on the worker):
```bash
aws ssm start-session \
  --target <MI_ID> \
  --region us-west-2
```

## Debugging Checklist

When a job fails, follow this sequence:

1. `get-job` — check `lifecycleStatusMessage` and `taskRunStatus`
2. `list-sessions` — find the session(s) for the job
3. `get-session` — get the log group/stream
4. Fetch logs from the beginning (`--start-from-head`) to see the full execution
5. Search for `"ERROR"` or `"exit code"` to find the failure point
6. Check worker logs (`workerLog` from get-session) if the session itself failed to start

Common failure patterns:
- "No such container" — Docker image pull failed, check ECR access
- "ComfyUI failed to start within 360s" — container startup issue, check docker logs in the session log
- "Registration with signature validation failed" — SSM registration issue
- "OOM" or "Killed" — out of memory, need larger instance or --lowvram
- Session never starts — fleet has no capacity, check fleet scaling
