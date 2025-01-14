# OpenSearch snapshotter

A docker image containing `bash`, `curl` and `jq` providing ability to take opensearch snapshot, verify last snapshot status and delete snapshots being out of retention period. 

# Overview

This script automates regular snapshot management of AWS OpenSearch Cluster.

## Scripts

- `opensearch_snapshotter.sh` - creates, verfies and deletes opensearch snapshots

### Environment Variables
- `AWS_REGION` AWS region of the sts endpoint,
- `AWS_ROLE_ARN` AWS role to assume,
- `DEBUG_LEVEL` (optional) Set debug level [0-5].
- `OPENSEARCH_BASE_URL` Opensearch endpoint URL (proto://host[:port]/) - trailing slash is required,
- `SNAPSHOT_REPOSITORY` name of the OpenSearch snapshot repository,
- `SNAPSHOT_RETENTION_DAYS` snapshot retention period in days,
- `SLACK_MONITORING_WEBHOOK` (optional) Slack webhook URL to send notifications to.

## Usage

`./scripts/opensearch_snapshotter.sh <take_snapshot|verify_snapshot|delete_old_snapshots>`

Pass required environment variables to the script and specify argument for action you want to perform.
