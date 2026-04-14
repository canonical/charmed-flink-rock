#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

get_flink_version() {
    # Extract flink version from rockcraft

    yq '(.version)' rockcraft.yaml
}

flink_image() {
    # Construct the image ref from Rock version

    # echo "ghcr.io/canonical/test-charmed-flink:$(get_flink_version)"
    echo "batalex/charmed-flink:2.2.0-entry4"
}

launch_jump_host() {
    # Create jump host pod from Flink test image
    #
    # Arguments:
    # $1: Namespace
    # $2: Service account
    # $3: Pod name

    namespace=$1
    sa=$2
    pod_name=$3

    echo "Creating jump host pod"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $namespace
spec:
  serviceAccountName: $sa
  containers:
  - name: flink-cli
    image: $(flink_image)
    imagePullPolicy: IfNotPresent
    command: ["sleep", "infinity"]
EOF

    echo "Waiting for jump host to be ready..."
    kubectl wait --for=condition=Ready pod/$pod_name -n $namespace --timeout=60s
}
