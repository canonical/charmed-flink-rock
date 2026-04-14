#!/usr/bin/env bash
# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

source ./tests/utils/k8s_utils.sh
source ./tests/utils/flink_utils.sh
source ./tests/utils/s3_utils.sh

# Make sure that we have credentials to an S3-compliant object storage
if [[ -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" || -z "$S3_ENDPOINT" ]]; then
    echo "Error: Object storage is not configured with env vars"
    exit 1
fi

NAMESPACE="test-flink-ns"
SERVICE_ACCOUNT="testflink"
JUMP_POD_NAME="flink-jump-host"
HS_SVC_NAME="flink-history-server"
CLUSTER_ID="wordcount-cluster"

get_hs_service_endpoint() {
    # Construct the endpoint to access the history server
    echo "http://$(kubectl get svc -n $NAMESPACE $HS_SVC_NAME -o jsonpath='{.spec.clusterIP}'):8082"
}

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
        -Dkubernetes.taskmanager.cpu=1 \
        local:///opt/flink/examples/streaming/WordCount.jar

    kubectl wait --for=condition=Available --timeout=30s deploy/${CLUSTER_ID} -n ${NAMESPACE} || exit 1
    wait_for_taskmanager $NAMESPACE

    echo "Display live logs"

    containers_logs=$(kubectl logs -f -l app=${CLUSTER_ID} --all-containers=true --prefix -n ${NAMESPACE} | tee /dev/tty)

    grep -E "Job [A-Za-z0-9]+ reached terminal state FINISHED" <<<"$containers_logs"
    grep "(ophelia,1)" <<<"$containers_logs"
}

test_deploy_history_server() {
    # Deploy the History Server, make sure it properly runs
    echo "Creating History Server deployment and service."
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flink-history-server
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: flink-history-server
  template:
    metadata:
      labels:
        app: flink-history-server
    spec:
      serviceAccountName: $SERVICE_ACCOUNT
      containers:
        - name: history-server
          image: $(flink_image)
          args: ["history-server"] 
          env:
            - name: ENABLE_BUILT_IN_PLUGINS
              value: "flink-s3-fs-presto-2.2.0.jar"
            - name: FLINK_PROPERTIES
              value: |
                historyserver.archive.fs.dir: s3://test-flink/flink-events/
                historyserver.archive.fs.refresh-interval: 5000
                historyserver.web.port: 8082
                s3.access-key: $S3_ACCESS_KEY
                s3.secret-key: $S3_SECRET_KEY
                s3.endpoint: $S3_ENDPOINT

          ports:
            - containerPort: 8082
              name: webui
---
apiVersion: v1
kind: Service
metadata:
  name: flink-history-server
  namespace: $NAMESPACE
spec:
  type: ClusterIP
  ports:
    - port: 8082
      targetPort: 8082
  selector:
    app: flink-history-server

EOF
    kubectl wait --for=condition=Available --timeout=60s deploy/flink-history-server -n ${NAMESPACE} || exit 1
    kubectl rollout status --timeout=60s deploy/flink-history-server -n ${NAMESPACE}
    sleep 5

    curl "$(get_hs_service_endpoint)"/jobs/overview
}

test_example_job_archived_s3() {
    # Check that an archived job can be found in the history server

    echo "Running Flink example job"

    kubectl exec -it "$JUMP_POD_NAME" -n "$NAMESPACE" -- \
        /opt/flink/bin/flink run \
        --target kubernetes-application \
        -Dkubernetes.cluster-id="$CLUSTER_ID" \
        -Dkubernetes.container.image.ref="$(flink_image)" \
        -Dkubernetes.namespace="$NAMESPACE" \
        -Dkubernetes.service-account="$SERVICE_ACCOUNT" \
        -Dkubernetes.jobmanager.cpu=1 \
        -Dkubernetes.taskmanager.cpu=1 \
        -Dcontainerized.master.env.ENABLE_BUILT_IN_PLUGINS=flink-s3-fs-presto-2.2.0.jar \
        -Dcontainerized.taskmanager.env.ENABLE_BUILT_IN_PLUGINS=flink-s3-fs-presto-2.2.0.jar \
        -Djobmanager.archive.fs.dir=s3://test-flink/flink-events/ \
        -Ds3.access-key="$S3_ACCESS_KEY" \
        -Ds3.secret-key="$S3_SECRET_KEY" \
        -Ds3.endpoint="$S3_ENDPOINT" \
        local:///opt/flink/examples/streaming/WordCount.jar

    kubectl wait --for=condition=Available --timeout=30s deploy/${CLUSTER_ID} -n ${NAMESPACE} || exit 1
    wait_for_taskmanager $NAMESPACE

    echo "Display live logs"

    containers_logs=$(kubectl logs -f -l app=${CLUSTER_ID} --all-containers=true --prefix -n ${NAMESPACE} | tee /dev/tty)

    grep -E "Job [A-Za-z0-9]+ reached terminal state FINISHED" <<<"$containers_logs"
    grep "(ophelia,1)" <<<"$containers_logs"

    echo "Checking that job can be found in history server"
    jobs=$(curl "$(get_hs_service_endpoint)"/jobs/overview | yq '.jobs')
    echo $jobs
    grep "FINISHED" <<<$jobs
}

### TESTS ###

echo -e "##################################"
echo -e "RUN EXAMPLE JOB"
echo -e "##################################"

(setup_namespace_and_sa $NAMESPACE $SERVICE_ACCOUNT &&
    launch_jump_host $NAMESPACE $SERVICE_ACCOUNT $JUMP_POD_NAME &&
    test_example_job &&
    tear_down $NAMESPACE) || tear_down_failure $NAMESPACE

echo -e "##################################"
echo -e "DEPLOY HISTORY SERVER"
echo -e "##################################"

# Don't tear down in case of success here
(setup_namespace_and_sa $NAMESPACE $SERVICE_ACCOUNT &&
    test_deploy_history_server) || tear_down_failure

echo -e "##################################"
echo -e "RUN EXAMPLE JOB AND ARCHIVE STATS"
echo -e "##################################"

(launch_jump_host $NAMESPACE $SERVICE_ACCOUNT $JUMP_POD_NAME &&
    test_example_job_archived_s3 &&
    tear_down $NAMESPACE) || tear_down_failure $NAMESPACE
