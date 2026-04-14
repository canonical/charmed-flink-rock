# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.


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
