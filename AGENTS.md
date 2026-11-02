# Repository Engineering Context

`transport-d` is a shared workspace research package for byte-resource access
used by `imageio-d`, `dunia` and other consumers. Keep the package narrow:
transport owns access, limits, provenance and errors; consumers interpret the
returned bytes. Do not add image codecs, OSM parsing, raster semantics,
general caches or schedulers without an explicit workspace decision.

Read the workspace canonical documents under `../.workspace/` before changing
architecture, API, testing, release or toolchain policy.
