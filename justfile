# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

# Load S3 creds and endpoint
set dotenv-load

# Lint and format files
lint:
    yamllint --no-warnings rockcraft.yaml
    shfmt -l -w -i 4 tests
    
# Pack the rock
pack:
    rockcraft pack

# Clean environment: file and lxd container
clean:
    rm *.rock || true
    rockcraft clean

# Test Rock
test-rock:
    /bin/bash tests/test_rock.sh
