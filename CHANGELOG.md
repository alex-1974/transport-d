# Changelog

## 0.1.0

Initial synchronous transport release candidate.

- bounded range reads from memory and files;
- bounded segmented buffering through containers-d 0.3.1;
- synchronous HTTP Range GET and PUT support;
- explicit source/sink limits, errors and provenance;
- sequential reader/writer adapters;
- executor-injected asynchronous source API;
- DMD/LDC tests and local HTTP integration coverage.

The package does not own retries, caches, schedulers, image codecs, OSM
parsers or raster semantics.
