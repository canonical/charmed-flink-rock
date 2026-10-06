#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

set -eu

source ./tests/utils/k8s_utils.sh
source ./tests/utils/flink_utils.sh

if [[ -z "${S3_ACCESS_KEY:-}" || -z "${S3_SECRET_KEY:-}" || -z "${S3_ENDPOINT:-}" ]]; then
    echo "Error: Object storage is not configured with env vars"
    exit 1
fi

NAMESPACE="test-flink-ns"
SERVICE_ACCOUNT="testflink"
JUMP_POD_NAME="flink-jump-host"
HS_SVC_NAME="flink-history-server"
CLUSTER_ID="wordcount-cluster"

get_hs_service_endpoint() {
    echo "http://$(kubectl get svc -n "$NAMESPACE" "$HS_SVC_NAME" -o jsonpath='{.spec.clusterIP}'):8082"
}

deploy_history_server() {
    echo "Creating History Server deployment and service."
    export NAMESPACE SERVICE_ACCOUNT HS_SVC_NAME CLUSTER_ID IMAGE
    IMAGE=$(flink_image)
    envsubst <tests/resources/history-server.yaml.templ | kubectl apply -f -

    kubectl wait --for=condition=Available --timeout=60s deploy/flink-history-server -n ${NAMESPACE}
    kubectl rollout status --timeout=60s deploy/flink-history-server -n ${NAMESPACE}
    sleep 15

    curl "$(get_hs_service_endpoint)"/jobs/overview
}

run_archived_job() {
    echo "Running Flink example job"

    kubectl exec "$JUMP_POD_NAME" -n "$NAMESPACE" -- \
        /opt/flink/bin/flink run \
        --target kubernetes-application \
        -Dkubernetes.cluster-id="$CLUSTER_ID" \
        -Dkubernetes.container.image.ref="$(flink_image)" \
        -Dkubernetes.namespace="$NAMESPACE" \
        -Dkubernetes.service-account="$SERVICE_ACCOUNT" \
        -Dkubernetes.jobmanager.cpu=0.5 \
        -Dkubernetes.taskmanager.cpu=0.5 \
        -Dcontainerized.master.env.ENABLE_BUILT_IN_PLUGINS="flink-s3-fs-presto-$(flink_version).jar" \
        -Dcontainerized.taskmanager.env.ENABLE_BUILT_IN_PLUGINS="flink-s3-fs-presto-$(flink_version).jar" \
        -Djobmanager.archive.fs.dir=s3://test-flink/flink-events/ \
        -Ds3.access-key="$S3_ACCESS_KEY" \
        -Ds3.secret-key="$S3_SECRET_KEY" \
        -Ds3.endpoint="$S3_ENDPOINT" \
        local:///opt/flink/examples/streaming/WordCount.jar

    kubectl wait --for=condition=Available --timeout=60s deploy/${CLUSTER_ID} -n ${NAMESPACE}
    wait_for_taskmanager "$NAMESPACE"
    echo "Waiting for job completion"

    containers_logs=$(kubectl logs -f -l app=${CLUSTER_ID} --all-containers=true --prefix -n ${NAMESPACE})
    echo "$containers_logs"

    grep -E "Job [A-Za-z0-9]+ reached terminal state FINISHED" <<<"$containers_logs"
    grep "(ophelia,1)" <<<"$containers_logs"

    echo "Checking that job can be found in history server"
    sleep 15
    jobs=$(curl "$(get_hs_service_endpoint)"/jobs/overview | yq '.jobs')
    echo "$jobs"
    grep "FINISHED" <<<"$jobs"
}

echo -e "##################################"
echo -e "DEPLOY HISTORY SERVER"
echo -e "##################################"

(
    setup_namespace_and_sa "$NAMESPACE" "$SERVICE_ACCOUNT" &&
        deploy_history_server
) || tear_down_failure "$NAMESPACE"

echo -e "##################################"
echo -e "RUN EXAMPLE JOB AND ARCHIVE STATS"
echo -e "##################################"

(
    launch_jump_host "$NAMESPACE" "$SERVICE_ACCOUNT" "$JUMP_POD_NAME" &&
        run_archived_job &&
        tear_down "$NAMESPACE"
) || tear_down_failure "$NAMESPACE"
