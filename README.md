# launchpad-blueprints
This repository contains the assets used by launchpad.

launchpad project's [env/BLUEPRINTS_VERSION](https://github.com/RocketChat/launchpad/blob/develop/env/BLUEPRINTS_VERSION) 
defines the [tag that will be used](https://github.com/RocketChat/launchpad/blob/56ccd6b8f2fa86a2639a3d0c795d6a781ebfbd86/assets/Makefile#L24) 
at build time to embed `/manifests/*`.

launchpad and blueprint tags don't necessarily need to be identical. By specifying a release tag in this repository, we understand that manifests 
(all versioned sets, like `/manifests/v1alpha1`, ..., `/manifests/vN`) are ready to be embedded, so newer launchpad versions can understand  
and can absorb improvements for older versioned sets (within a versioned set major -- must not break), so commands
[can satisfy declarations](https://github.com/RocketChat/launchpad/blob/56ccd6b8f2fa86a2639a3d0c795d6a781ebfbd86/assets/version.go#L17-L23) `assets: blueprints/v1alpha1`, ..., `assets: blueprints/vN`).
