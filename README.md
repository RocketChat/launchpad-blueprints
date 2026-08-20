# Launchpad Blueprints

This repository contains the official blueprint assets, Kubernetes manifests, and packaging specifications used by **Rocket.Chat Launchpad**.

---

## 1. Overview

Launchpad blueprints provide the declarative Kubernetes foundation for deploying Rocket.Chat infrastructure, operators, and supporting services across online, offline (air-gapped), and custom enterprise environments.

The repository is organized into two primary categories:
- **`manifests/`**: Versioned Kubernetes manifest sets organized by API group (e.g. [`manifests/v1alpha1`](manifests/v1alpha1/README.md)).
- **`pkg/`**: Versioned packaging definitions declaring images, charts, and manifest sources for air-gap bundle generation (e.g. [`pkg/v1alpha1`](pkg/v1alpha1/README.md)).

---

## 2. Versioning & Decoupling Model

Launchpad CLI releases and Blueprint release tags are intentionally decoupled:

1. **Build-Time Embedding**:
   - The Launchpad CLI repository maintains [`env/BLUEPRINTS_VERSION`](https://github.com/RocketChat/launchpad/blob/develop/env/BLUEPRINTS_VERSION) to define the default blueprint release tag fetched and embedded into the binary at compile time.
2. **Independent Lifecycle**:
   - Blueprint tags (e.g. `v1.4.1-alpha1`) represent stable, tested collections of manifests across all supported API versions (`/manifests/v1alpha1`, etc.).
   - Launchpad CLI can deploy embedded blueprints out-of-the-box, fetch upstream release tags dynamically at runtime, or load external custom manifests via `--manifests <dir_or_url>` and `--package <file.tar.zst>`.
3. **Compatibility Invariants**:
   - Updates within a given API version (e.g. `/manifests/v1alpha1`) must remain backwards-compatible and preserve expected component names, labels, and namespaces (`launchcontrol-system`, `airlock-system`, `traefik`, etc.).
   - Breaking structural changes must introduce a new version directory (e.g. `/manifests/v1beta1` or `/manifests/v1`).

---

## 3. Specifications & Reference Documentation

Detailed schemas, directory layouts, and configuration references are documented in their respective directories:

- **Blueprint Manifests & Custom Overrides**: See [`manifests/v1alpha1/README.md`](manifests/v1alpha1/README.md) for the `BlueprintManifests` (`metadata.yaml`) schema, directory invariants, and WYSIWYG preset rules.
- **Air-Gap Package Specifications**: See [`pkg/v1alpha1/README.md`](pkg/v1alpha1/README.md) for the `BlueprintPackage` recipe schema, image/chart declarations, and packaging workflow.
