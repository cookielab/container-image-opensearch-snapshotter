#!/usr/bin/env bash

# Name: opensearch-snapshotter
# Author: devops@cookielab.io
# Created: 2024-12-16

set -ue

NEW_SNAPSHOT_NAME="daily-$(date +%F-%T | tr ':' '-')"
TIMESTAMP=$(date +%s)

## Getting short lived credentials from service account
TOKEN_FILE='/var/run/secrets/eks.amazonaws.com/serviceaccount/token'
export AWS_REGION='eu-west-1'
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_TOKEN_EXPIRATION
read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_TOKEN_EXPIRATION < <(
	curl \
		--silent \
		--request POST \
		--header "Content-Type: application/x-www-form-urlencoded" \
		--header 'Accept: application/json' \
		--data "Action=AssumeRoleWithWebIdentity&RoleArn=${AWS_ROLE_ARN}&RoleSessionName=k8s-session&WebIdentityToken=$(<"$TOKEN_FILE")&Version=2011-06-15" \
		"https://sts.${AWS_REGION}.amazonaws.com/" \
		| jq --raw-output '.AssumeRoleWithWebIdentityResponse.AssumeRoleWithWebIdentityResult.Credentials | "\(.AccessKeyId)\t\(.SecretAccessKey)\t\(.SessionToken)\t\(.Expiration)"'
)

function __msg(){
	printf '%s' "$1"
}

function __msgnl(){
	printf '%s\n' "$1"
}

function __es_curl(){
	CURL_OPTS=(
		'-w' '\n'
		'--silent'
		'--http1.1'
		'--fail'
		'--aws-sigv4' "aws:amz:$AWS_REGION:es" \
		'--user' "$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY"
		'--header' "x-amz-security-token:$AWS_SESSION_TOKEN" \
		'--header' 'Content-Type: application/json'
		"${CURL_EXTRA_OPTS[@]}"
	)
	curl "${CURL_OPTS[@]}" "$OPENSEARCH_BASE_URL$1" 
	unset CURL_EXTRA_OPTS;
}

function __es_curl_get(){
	CURL_EXTRA_OPTS+=('--request' 'GET')
	__es_curl "$1" --request GET
}

function __es_curl_post(){
	CURL_EXTRA_OPTS+=('--request' 'POST' '--data' '@/dev/stdin')
	__es_curl "$1"
}

function __es_curl_put(){
	CURL_EXTRA_OPTS+=('--request' 'PUT' '--data' '@/dev/stdin')
	__es_curl "$1"
}

function __es_curl_delete(){
	CURL_EXTRA_OPTS+=('--request' 'DELETE')
	__es_curl "$1"
}

function get_snapshots(){
	__es_curl_get "_snapshot/$SNAPSHOT_REPOSITORY/_all"
}

function take_snapshot(){
	__es_curl_put "_snapshot/$SNAPSHOT_REPOSITORY/$NEW_SNAPSHOT_NAME" <<-EOF
		{
		  "ignore_unavailable": true,
		  "include_global_state": true,
		  "partial": true
		}
	EOF
}

function delete_old_snapshots(){
	snapshots_response=$(get_snapshots)
	jq --compact-output '.snapshots[]' <<<"$snapshots_response" | \
		while read -r snapshot
		do
			snapshot_name=$(echo "$snapshot" | jq --raw-output '.snapshot')
			snapshot_start_time=$(( $(jq --raw-output '.start_time_in_millis' <<<"$snapshot") / 1000 ))
			snapshot_age_days=$(( (TIMESTAMP - snapshot_start_time) / 86400 ))
			
			if (( snapshot_age_days > SNAPSHOT_RETENTION_DAYS))
			then
				__msg "Deleting snapshot: $snapshot_name (age: $snapshot_age_days days, retention: $SNAPSHOT_RETENTION_DAYS): "
				__es_curl_delete "_snapshot/$SNAPSHOT_REPOSITORY/$snapshot_name"
			else
				[[ -n $DEBUG ]] && __msgnl "Keeping snapshot $snapshot_name (age: $snapshot_age_days days, retention $SNAPSHOT_RETENTION_DAYS)"
			fi
		done

	__msg "Cleanup repository of unreferenced data: "
	__es_curl_post "_snapshot/$SNAPSHOT_REPOSITORY/_cleanup" <<<'{ "timeout": 600, "cluster_manager_timeout": 600 }'
}

function verify_last_snapshot(){
	last_snapshot=$(get_snapshots | jq '.snapshots[-1]')
	snapshot_name=$(jq --raw-output '.snapshot' <<<"$last_snapshot")

	if [[ $(jq --raw-output '.state' <<<"$last_snapshot") == "SUCCESS" ]]
	then
		__msgnl "Snapshot $snapshot_name finished successfully"
	else
		__msgnl "Snapshot $snapshot_name failed"
		if [[ -n $SLACK_MONITORING_WEBHOOK ]]
		then
			__msg "Sending slack notification: "
			curl \
				--fail \
				--header 'Content-type: application/json' \
				--request POST \
				"$SLACK_MONITORING_WEBHOOK" \
				--json @- <<-EOT
				{
					"text": "Snapshot \`${snapshot_name}\` failed see <${OPENSEARCH_BASE_URL}_dashboards/api/ism/_snapshots/$snapshot_name?repository=$SNAPSHOT_REPOSITORY|status>"
				}
			EOT
		else
			__msg 'SLACK_MONITORING_WEBHOOK not provided, skipping notification'
		fi
	fi
}

function run(){
	case $1 in
		verify_last_snapshot)
			verify_last_snapshot
		;;
		take_snapshot)
			take_snapshot
		;;
		delete_old_snapshots)
			delete_old_snapshots
		;;
	esac
}

run "$@"

# vim:foldmethod=indent:foldlevel=0
