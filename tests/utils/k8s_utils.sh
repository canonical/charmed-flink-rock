#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Check that kubectl is in the PATH and that it is properly configure to access the
# K8s cluster.
if ! kubectl get ns >>/dev/null; then
    echo "Error: The K8s cluster has not been configured properly. Exiting..."
    exit 1
fi

setup_namespace_and_sa() {
    # Create test namespace and service account
    #
    # Arguments
    # $1: Namespace to run the tests
    # $2: Service account name to run the tests

    export NAMESPACE=$1
    export SERVICE_ACCOUNT=$2

    echo "Setting up Namespace and Service account"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    envsubst <tests/resources/rbac-setup.yaml.tmpl | kubectl apply -f -
}

wait_for_pod_by_label() {
    # Wait for the given pod in the given namespace to be ready.
    #
    # Arguments:
    # $1: (Unique) label of the pod
    # $2: Namespace that contains the pod

    label=$1
    namespace=$2

    echo "Waiting for pod with label '$label' to become ready..."
    kubectl wait --for=condition=Ready pod -l $label -n $namespace --timeout=120s || return 1
}

wait_for_taskmanager() {
    # Wait for a taskmanager pod to spawn, then wait for it to be ready.
    #
    # In Flink, each pod outputs its own logs. One way to get the result of a sink
    # without a fancy logging setup is to wait until the pod is ready, then monitor its logs
    # using kubectl logs.
    #
    # Arguments:
    # $1: Namespace

    namespace=$1
    local label="component=taskmanager"
    local timeout_seconds=120
    local start_time=$(date +%s)

    echo "Waiting for TaskManager to appear (Timeout: ${timeout_seconds}s)..."

    # A Flink deployment is created first, then a JobManager, then a TaskManager
    # We need wait for this last pod to appear before we can wait for a specific status.
    until kubectl get pods -n "$NAMESPACE" -l "$label" -o name | grep -q "pod/"; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        kubectl get pods -n "$NAMESPACE"

        if [ "$elapsed" -ge "$timeout_seconds" ]; then
            echo "Error: Timed out waiting for TaskManager pod to appear."
            exit 1
        fi
        sleep 10
    done

    wait_for_pod_by_label $label $namespace
}

tear_down() {
    # Tear down test namespace
    #
    # Arguments:
    # $1: Namespace

    namespace=$1
    echo "Tearing down resources"
    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
        echo "Deleting namespace $namespace..."
        kubectl delete namespace "$namespace" --wait=true
        echo "Cleanup complete."
    else
        echo "Namespace $namespace already gone."
    fi
}

tear_down_failure() {
    # Tear down and exit 1.
    #
    # Arguments:
    # $1: Namespace

    namespace=$1
    tear_down $namespace
    exit 1
}
