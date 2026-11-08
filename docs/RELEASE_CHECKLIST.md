# transport-d 0.2.0 release checklist

- [x] `containers-d` dependency is pinned to released `0.3.1`.
- [x] `error-d` result migration is implemented and tested locally.
- [x] Generic bounded HTTP exchange is implemented and documented.
- [x] Synchronous source/sink/range API is tested with DMD and LDC2.
- [x] File lifecycle and bounded transfer behavior are tested.
- [x] HTTP Range GET and segmented PUT are covered by a local integration test.
- [x] Provenance, response metadata and observation metrics are available.
- [x] Executor-injected asynchronous source API is documented and tested with
  the deterministic inline executor.
- [x] Consumer-shaped OSM/imagery range probe exists.
- [ ] Replace the local `error-d` path dependency with a registry-resolvable release.
- [ ] Run consumer qualification against the breaking result API.
- [ ] Promote the qualified release branch to `main`.
- [ ] Create the annotated release tag `v0.2.0`.
- [ ] Publish the release and verify DUB resolution from the registry.

The unchecked items are repository/release operations, not implementation
gates.
