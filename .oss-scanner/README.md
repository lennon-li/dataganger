# Anthropic OSS Scanner enrollment preparation

Canonical enrollment: https://github.com/anthropics/oss-scanner

The enrollment PR belongs in **anthropics/oss-scanner**, under `projects/dataganger/project.yaml`; do not open it until the maintainer approves.

Proposed enrollment configuration:

```yaml
repo: https://github.com/lennon-li/dataganger
primary_contact: yeli@biostats.ai
homepage: https://dataganger.biostats.ai/
dockerfile: .oss-scanner/Dockerfile
threat_model: .oss-scanner/threat_model.md
```

## Validate before enrollment
From the DataGangeR root:

```sh
docker build --pull -f .oss-scanner/Dockerfile -t dataganger-oss-scanner .
docker run --rm --network none dataganger-oss-scanner Rscript -e 'library(dataganger); stopifnot(packageVersion("dataganger") >= "0.9.0")'
docker run --rm --network none dataganger-oss-scanner Rscript -e 'testthat::test_local("/src")'
```

In a checkout of anthropics/oss-scanner, add the proposed project.yaml at projects/dataganger/project.yaml, then run:

```sh
python3 tools/validate.py
tools/check dataganger
```

The official `tools/check` additionally installs Claude Code and launches the resulting container without network access. Do not claim enrollment readiness until both the Docker build and official checks pass. No enrollment PR is created by this preparation.
