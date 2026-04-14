#!/bin/bash

source ./tests/utils/k8s_utils.sh
source ./tests/utils/flink_utils.sh

NAMESPACE="test-flink-ns"
SERVICE_ACCOUNT="testflink"
JUMP_POD_NAME="flink-jump-host"
CLUSTER_ID="wordcount-cluster"

test_example_job() {
    # Run the example job WordCount.
    # Assert that the job successfully finished and
    # that the TaskManager outputed one of the expected logs
    echo "Running Flink example job"

    kubectl exec -it "$JUMP_POD_NAME" -n "$NAMESPACE" -- \
        /opt/flink/bin/flink run \
        --target kubernetes-application \
        -Dkubernetes.cluster-id="$CLUSTER_ID" \
        -Dkubernetes.container.image.ref="$(flink_image)" \
        -Dkubernetes.namespace="$NAMESPACE" \
        -Dkubernetes.service-account="$SERVICE_ACCOUNT" \
        -Dkubernetes.jobmanager.cpu=1 \
        -Dkubernetes.taskmanager.cpu=0.5 \
        local:///opt/flink/examples/streaming/WordCount.jar

    kubectl wait --for=condition=Available --timeout=30s deploy/${CLUSTER_ID} -n ${NAMESPACE} || exit 1
    wait_for_taskmanager $NAMESPACE

    echo "Getting logs"

    containers_logs=$(kubectl logs -f -l app=${CLUSTER_ID} --all-containers=true --prefix -n ${NAMESPACE} | tee /dev/tty)

    grep -E "Job [A-Za-z0-9]+ reached terminal state FINISHED" <<<"$containers_logs"
    grep "(ophelia,1)" <<<"$containers_logs"
}

(setup_namespace_and_sa $NAMESPACE $SERVICE_ACCOUNT &&
    launch_jump_host $NAMESPACE $SERVICE_ACCOUNT $JUMP_POD_NAME &&
    test_example_job &&
    tear_down $NAMESPACE) || tear_down_failure $NAMESPACE
