# Consumer contract decision

Status: accepted for transport-d 0.1.x. This document records the decision
for the `imageio-d` and `osm-d` consumer requests without adding consumer
specific format or decoding policy.

| Requirement | Decision | Transport API |
| --- | --- | --- |
| Bounded exact random access | Core | `ByteSource.read(ByteRange, ...)` |
| Short bounded reads and unambiguous EOF | Core | `ByteSource.readSome(...)`; a short successful result is followed by `endOfSource` |
| Source length and range capability | Core, optional | `ByteSource.sourceInfo` |
| HTTP status, length and Content-Range | Backend metadata | `HttpSource.responseInfo` |
| Provenance without credentials | Core | `provenance` / `SourceInfo` |
| Request and byte accounting | Opt-in core decorator | `ObservedSource` |
| Bounded chunked storage | Core byte facility | `SegmentedByteBuffer` |
| Local-file/HTTP range parity | Core contract | exact reads remain strict; partial reads use `readSome` |

Exact random-access reads never fall back to downloading the complete resource.
`readSome` is the bounded sequential/refill operation for consumers whose next
read may cross EOF. `invalidRange`, `rangeUnavailable`, `endOfSource` and
`sourceFailure` remain distinct transport outcomes.

The following remain consumer responsibilities and are deliberately excluded:
TIFF/COG parsing, tile and overview selection, decompression, decoded pixels,
OSM/XML parsing, schedulers, retries and general caches.
