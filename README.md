# Charmed Apache Flink rock

[![Container Registry](https://img.shields.io/badge/Container%20Registry-published-blue)](https://github.com/canonical/charmed-flink-rock/pkgs/container/charmed-flink)
[![Release](https://github.com/canonical/charmed-flink-rock/actions/workflows/publish.yaml/badge.svg)](https://github.com/canonical/charmed-flink-rock/actions/workflows/publish.yaml)

This repository contains the packaging metadata for creating a Charmed Apache Flink rock (OCI compliant image).

For more information on rocks, visit the [rockcraft Github](https://github.com/canonical/rockcraft).

## Building the ROCK

The steps outlined below are based on the assumption that you are building the ROCK with the latest LTS of Ubuntu.\
If you are using another version of Ubuntu or another operating system, the process may be different.
To avoid any issue with other operating systems you can simply build the image with [multipass](https://multipass.run/):

```bash
sudo snap install multipass
multipass launch 24.04 -n rock-dev
multipass shell rock-dev
```

### Clone repository

```bash
git clone https://github.com/canonical/charmed-flink-rock.git
cd charmed-flink-rock
```

### Installing tooling

```bash
sudo snap install rockcraft --classic
sudo apt install podman
```

### Packing and Running the ROCK

```bash
rockcraft pack
podman load < charmed-flink_2.2.0_amd64.rock
podman run -it --rm --name flink --entrypoint /bin/bash localhost/2.2.0:latest
```

## Licence statement

Charmed Apache Flink is free software, distributed under the [Apache Software License, version 2.0](licenses/LICENSE-rock).

## Trademark Notice

Apache®, Apache Flink, Flink®, and the Flink logo are either registered trademarks or trademarks of the Apache Software Foundation in the United States and/or other countries.
