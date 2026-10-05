#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

get_flink_version() {
    # Extract flink version from rockcraft

    yq '(.version)' rockcraft.yaml
}

flink_image() {
    # Use the exact OCI reference embedded during refine and loaded by CI/spread.

    just get-oci
}

launch_jump_host() {
    # Create jump host pod from Flink test image
    #
    # Arguments:
    # $1: Namespace
    # $2: Service account
    # $3: Pod name

    export NAMESPACE=$1
    export SERVICE_ACCOUNT=$2
    export POD_NAME=$3
    export IMAGE=$(flink_image)

    echo "Creating jump host pod"
    envsubst <tests/resources/jump-host.yaml.templ | kubectl apply -f -

    echo "Waiting for jump host to be ready..."
    kubectl wait --for=condition=Ready pod/$POD_NAME -n $NAMESPACE --timeout=60s
}
