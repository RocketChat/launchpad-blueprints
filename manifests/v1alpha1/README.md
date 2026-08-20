# Launchpad Blueprint Manifests (`v1alpha1`)

This directory contains the Kubernetes manifests and blueprint metadata for Rocket.Chat Launchpad deployments.

## Directory Structure

A valid Launchpad blueprint directory contains a root `metadata.yaml` alongside component manifest folders:

```text
manifests/v1alpha1/
├── metadata.yaml             # Required: Blueprint specification & version metadata
├── airlock/                  # CRDs, RBAC, and controller deployment for Airlock
├── cert-manager/             # Cert-Manager HelmChart & ClusterIssuers
├── helm-controller/          # K3s Helm Controller CRDs & Deployment
├── launchcontrol/            # Rocket.Chat Launchcontrol operator & CRDs
├── longhorn/                 # Longhorn distributed block storage HelmChart
├── mongodbcommunity/         # MongoDB Community operator & CRDs
├── mongosh/                  # MongoDB shell utility pods
├── monitoring/               # Monitoring HelmChart & PodMonitors
├── seaweedfs/                # SeaweedFS operator & CSI driver
└── traefik/                  # Traefik ingress controller HelmChart
```

> [!IMPORTANT]
> **Component Structure and Naming Invariant**:
> When authoring custom blueprints, component directory names, resource names, labels, and target namespaces (e.g. `launchcontrol-system`, `airlock-system`, `traefik`, `cert-manager`) must be preserved as expected by the Launchpad `v1alpha1` reconciliation engine.

---

## `metadata.yaml` Specification

Every blueprint directory **must** contain a `metadata.yaml` declaring `kind: BlueprintManifests`:

```yaml
apiVersion: launchpad.cloud.rocket.chat/v1alpha1
kind: BlueprintManifests
version: "v1.4.1-alpha1"        # Unique version identifier
baseVersion: "v1.4.1-alpha1"    # Upstream release tag derived from
allowPresetOverrides: true      # Whether Launchpad size presets may mutate replicas/resources
description: "Rocket.Chat Launchpad standard blueprint manifests"
author: "Rocket.Chat Cloud Team <cloud.team@rocket.chat>"
```

### Field Reference

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `apiVersion` | `string` | **Yes** | Must be `launchpad.cloud.rocket.chat/v1alpha1`. |
| `kind` | `string` | **Yes** | Must be `BlueprintManifests`. |
| `version` | `string` | **Yes** | The semantic version or custom identifier of this blueprint release. |
| `baseVersion` | `string` | Optional | The upstream base version tag. Required for custom blueprints. If omitted, defaults to `version`. |
| `allowPresetOverrides` | `bool` | Optional | Defaults to `true` for standard blueprints, `false` for custom blueprints. Controls whether size presets (`micro`, `small`, `medium`, `large`) mutate CPU/memory/replicas. |
| `description` | `string` | Optional | Human-readable description of the blueprint bundle. |
| `author` | `string` | Optional | Author or maintainer contact information. |

---

## Standard vs Custom Blueprints (`isCustom`)

Launchpad determines whether a blueprint is standard or custom dynamically:

$$\text{isCustom} = (\text{metadata.version} \neq \text{metadata.baseVersion})$$

- **Standard Blueprints (`version == baseVersion`)**: Size presets dynamically adjust CPU, memory requests/limits, storage, and replica counts based on `size` in `deploy.yaml`.
- **Custom Blueprints (`version != baseVersion`)**: Custom YAML manifests are preserved **WYSIWYG** (What You See Is What You Get). CPU/memory and replica counts are **never touched** unless `allowPresetOverrides: true` is explicitly enabled in `metadata.yaml`.
- **Air-Gap Private Registry Rewriting**: In all cases (standard and custom), private registry domain rewriting and `imagePullSecrets` injection always apply when private registry settings are configured in `deploy.yaml`.

---

## Deployment Usage

> [!NOTE]
> **Embedded Binary Fallback**:
> The Launchpad CLI binary embeds standard blueprints at compile time. For standard deployments, passing `--manifests` or `--package` is **not required**:
> ```bash
> launchpad deploy -f deploy.yaml
> ```
> Explicit flags (`--manifests` and `--package`) are intended for custom blueprint development or version overrides and should be used with caution.

### Explicit Blueprint Overrides

```bash
# 1. Deploy using a local blueprint directory
launchpad deploy -f deploy.yaml --manifests ./my-custom-blueprints

# 2. Deploy using a remote tar.gz archive URL
launchpad deploy -f deploy.yaml --manifests https://git.example.com/blueprints/-/archive/v1.0.tar.gz

# 3. Deploy using a generated .tar.zst package bundle
launchpad deploy -f deploy.yaml --package rocketchat-bundle-v1.4.1-alpha1-amd64.tar.zst
```
