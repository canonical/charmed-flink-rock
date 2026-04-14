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

    namespace=$1
    sa=$2
    echo "Setting up Namespace and Service account"
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $sa
  namespace: $namespace
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: $namespace
  name: flink-k8s-role
rules:
  - apiGroups: ["", "apps"]
    resources: ["pods", "services", "configmaps", "deployments"]
    verbs: ["get", "list", "watch", "create", "delete", "edit", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: flink-k8s-role-binding
  namespace: $namespace
subjects:
- kind: ServiceAccount
  name: $sa
roleRef:
  kind: Role
  name: flink-k8s-role
  apiGroup: rbac.authorization.k8s.io
EOF
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
    kubectl wait --for=condition=Ready pod -l $label -n $namespace --timeout=60s
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
    local timeout_seconds=60
    local start_time=$(date +%s)

    echo "Waiting for TaskManager to appear (Timeout: ${timeout_seconds}s)..."

    # A Flink deployment is created first, then a JobManager, then a TaskManager
    # We need wait for this last pod to appear before we can wait for a specific status.
    until kubectl get pods -n "$NAMESPACE" -l "$label" -o name | grep -q "pod/"; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ "$elapsed" -ge "$timeout_seconds" ]; then
            echo "Error: Timed out waiting for TaskManager pod to appear."
            exit 1
        fi
        sleep 2
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
