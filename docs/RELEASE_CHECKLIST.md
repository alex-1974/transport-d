# transport-d 0.1.0 release checklist

- [x] `containers-d` dependency is pinned to released `0.3.1`.
- [x] Synchronous source/sink/range API is tested with DMD and LDC2.
- [x] File lifecycle and bounded transfer behavior are tested.
- [x] HTTP Range GET and segmented PUT are covered by a local integration test.
- [x] Provenance, response metadata and observation metrics are available.
- [x] Executor-injected asynchronous source API is documented and tested with
  the deterministic inline executor.
- [x] Consumer-shaped OSM/imagery range probe exists.
- [ ] Create the release commit and tag `v0.1.0`.
- [ ] Publish the release and verify DUB resolution from the registry.

The unchecked items are repository/release operations, not implementation
gates.
