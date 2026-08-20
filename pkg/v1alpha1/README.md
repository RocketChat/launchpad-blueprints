# Launchpad Package Specifications (`v1alpha1`)

This directory contains package specifications used by `launchpad package generate` to build hermetic, air-gap-ready `.tar.zst` packages.

## Package Specification (`kind: BlueprintPackage`)

A package definition file (e.g. `bundle.yaml` or `package.yaml`) declares the container images, Helm charts, and blueprint manifests required for a full Launchpad environment:

```yaml
apiVersion: launchpad.cloud.rocket.chat/v1alpha1
kind: BlueprintPackage
name: launchpad-blueprints
manifestsVersion: "v1.4.1-alpha1"     # Upstream release tag (or manifestsSource: "../../manifests/v1alpha1")

images:
  - rocketchat/rocket.chat:8.5.1
  # ... (additional container images)

charts:
  - name: traefik
    url: https://helm.traefik.io/traefik/traefik-26.0.0.tgz
    version: 26.0.0
  # ... (additional Helm charts)
```

---

## Field Reference

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `apiVersion` | `string` | **Yes** | Must be `launchpad.cloud.rocket.chat/v1alpha1`. |
| `kind` | `string` | **Yes** | Must be `BlueprintPackage`. |
| `name` | `string` | **Yes** | Unique package bundle name (e.g. `launchpad-blueprints`). |
| `manifestsVersion` | `string` | Conditional | Upstream blueprint release tag to fetch and bundle into the package. Required if `manifestsSource` is omitted. |
| `manifestsSource` | `string` | Conditional | Local directory path or remote archive URL to bundle into the package. Required if `manifestsVersion` is omitted. |
| `version` | `string` | Optional | Package artifact version string. Defaults to the manifests version if omitted. |
| `images` | `string[]` | Optional | List of container images to download and bundle into the OCI layout. |
| `charts` | `object[]` | Optional | List of Helm chart archives to download and bundle. |

---

## Air-Gap Workflow: Package, Push & Deploy

In air-gapped environments, the full deployment workflow consists of three distinct stages:

### 1. Build the Package Bundle (Connected Machine)
```bash
launchpad package generate -s assets/pkg/v1alpha1/bundle.yaml
```
Generates a `.tar.zst` archive containing:
- **`oci/`**: Standard OCI image layout containing all declared container images.
- **`charts/`**: Downloaded Helm chart archives.
- **`blueprints/`**: Complete blueprint manifests and `metadata.yaml`.

### 2. Push Images and Charts to Private Registry (Air-Gapped Node)
```bash
launchpad package push -p rocketchat-enterprise-v1.4.1-alpha1-amd64.tar.zst -r registry.internal.acme.com
```
Extracts and pushes the container images and Helm charts from the `.tar.zst` package directly into the target private registry.

### 3. Deploy Workloads to Cluster
```bash
# Deploy using manifests directly extracted from the package bundle
launchpad deploy -f deploy.yaml --package rocketchat-enterprise-v1.4.1-alpha1-amd64.tar.zst
```
