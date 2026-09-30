#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

set -eu

source ./tests/utils/k8s_utils.sh
source ./tests/utils/flink_utils.sh

NAMESPACE="test-flink-ns"
SERVICE_ACCOUNT="testflink"
JUMP_POD_NAME="flink-jump-host"
CLUSTER_ID="wordcount-cluster"

run_example_job() {
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
        local:///opt/flink/examples/streaming/WordCount.jar

    kubectl wait --for=condition=Available --timeout=30s deploy/${CLUSTER_ID} -n ${NAMESPACE}
    wait_for_taskmanager "$NAMESPACE"
    echo "Waiting for job completion"

    containers_logs=$(kubectl logs -f -l app=${CLUSTER_ID} --all-containers=true --prefix -n ${NAMESPACE})
    echo "$containers_logs"

    grep -E "Job [A-Za-z0-9]+ reached terminal state FINISHED" <<<"$containers_logs"
    grep "(ophelia,1)" <<<"$containers_logs"
}

echo -e "##################################"
echo -e "RUN EXAMPLE JOB"
echo -e "##################################"

(
    setup_namespace_and_sa "$NAMESPACE" "$SERVICE_ACCOUNT" &&
        launch_jump_host "$NAMESPACE" "$SERVICE_ACCOUNT" "$JUMP_POD_NAME" &&
        run_example_job &&
        tear_down "$NAMESPACE"
) || tear_down_failure "$NAMESPACE"
