# Changelog

## 0.1.0

Initial synchronous transport release candidate.

- bounded range reads from memory and files;
- bounded segmented buffering through containers-d 0.3.1;
- synchronous HTTP Range GET and PUT support;
- explicit source/sink limits, errors and provenance;
- bounded partial reads with explicit EOF semantics and source capabilities;
- sequential reader/writer adapters;
- executor-injected asynchronous source API;
- DMD/LDC tests and local HTTP integration coverage.

The consumer contract decision for `imageio-d` and `osm-d` is recorded in
`docs/CONSUMER_CONTRACT.md`.

The package does not own retries, caches, schedulers, image codecs, OSM
parsers or raster semantics.
