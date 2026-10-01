# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Needed to load S3 creds and endpoint for the tests
set dotenv-load := true

raw_arch := arch()
arch := if raw_arch == "x86_64" { "amd64" } else if raw_arch == "aarch64" { "arm64" } else { raw_arch }

rock_name := `yq '.name' rockcraft.yaml`
rock_version := `yq '.version' rockcraft.yaml`
rock_source := `yq '."source-code"' rockcraft.yaml`
oci_name := "ghcr.io/canonical/" + rock_name + ":" + rock_version
rock_file := rock_name + "_" + rock_version + "_" + arch + ".rock"
tar_file := rock_name + "_" + rock_version + "_" + arch + ".tar"

# Lint and format files
lint:
    yamllint --no-warnings rockcraft.yaml spread.yaml tests/**/*.yaml tests/**/*.yaml.templ tests/**/*.yaml.tmpl
    shfmt -l -w -i 4 tests

# Pack the rock
pack:
    #!/usr/bin/env bash
    if [ -f "{{ rock_file }}" ]; then
        echo "Found existing rock: {{ rock_file }}"
        if [ -z "$(find rockcraft.yaml tests -newer {{ rock_file }} 2>/dev/null)" ]; then
            echo "Project files unchanged, reusing existing rock file."
            exit 0
        fi
        echo "Project files changed, re-packing."
    fi
    rockcraft pack

# Add additional labels to rock and export to K8s tar
refine: pack
    #!/usr/bin/env bash
    COMMIT_ID=$(git log -1 --format=%H)
    DESCRIPTION=$(yq .description rockcraft.yaml)

    rockcraft.skopeo copy "oci-archive:{{ rock_file }}" oci:to_process:latest
    regctl image mod ocidir://to_process:latest --replace \
        --label "org.opencontainers.image.revision=${COMMIT_ID}" \
        --label "org.opencontainers.image.source={{ rock_source }}" \
        --label "org.opencontainers.image.description=${DESCRIPTION}"

    regctl image export ocidir://to_process:latest \
        --name "{{ oci_name }}" \
        "{{ tar_file }}"
    rm -r to_process

# Clean environment: packed files and lxd container
clean:
    rm -f *.rock
    rm -f *.tar
    rockcraft clean

# Echo rock file
get-rock-file:
    @echo "{{rock_file}}"

# Echo refined tar file
get-tar-file:
    @echo "{{tar_file}}"

# Echo OCI
get-oci:
    @echo "{{oci_name}}"

# Test Rock - basic tests
test-basic:
    /usr/bin/env bash tests/test_basic/test.sh

# Test Rock - history server tests
test-history-server:
    /usr/bin/env bash tests/test_history_server/test.sh
