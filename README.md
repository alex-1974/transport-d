# transport-d

Shared byte-resource transport for `imageio-d`, `dunia` and other workspace
consumers.

Status: synchronous release candidate with an executor-injected asynchronous
API. HTTP retries, cancellation policy, caches and schedulers remain outside
the core package. This package does not parse images, OSM data or raster
semantics.

## Contract

```d
auto result = source.read(ByteRange(offset, length), destination[], limits);
```

The source reports the requested range, bytes returned and a structured error.
It must never silently replace a failed range read with a full-resource read.
`endOfSource` is reserved for sequential transfer termination; an invalid
requested range remains `invalidRange`.

Sinks use the same bounded, synchronous style:

```d
auto result = source.copyTo(new FileSink("output.bin"));
```

`copyTo` transfers bounded chunks and does not interpret the bytes. `FileSink`
overwrites its target by default; pass `true` as the second constructor
argument to explicitly append. HTTP,
retries, cancellation and cache policy remain separate backend/policy work.
Call `close()` explicitly when the transfer is complete; destruction is only a
fallback resource cleanup mechanism.

For sequential access, a source or sink can be adapted to a stream-shaped
interface:

```d
auto reader = new SourceReader(source);
auto writer = new SinkWriter(sink);
auto result = reader.copyTo(writer);
```

The reader owns only its current offset. The underlying source remains
range-based, so the same backend can serve both random-access consumers and
sequential transfers.

`HttpSource` provides synchronous HTTP range reads when the server honours the
`Range` request header. It reports connection, protocol and short-response
failures as `sourceFailure` or `rangeUnavailable`; it does not perform a
pre-flight ping.

`HttpOptions` makes operation timeout, connect timeout, redirect count and
user-agent explicit. `HttpSource.responseInfo` exposes the last response's
status, content length and content-range metadata.

`HttpSink` and `uploadTo` provide bounded synchronous PUT uploads. Payload
chunks are retained in independent segments and supplied to libcurl through
its send callback; the upload is performed on `close()` (or by `uploadTo`).
The configured maximum remains an explicit safety bound.

`SegmentedByteBuffer` is the transport consumer for bounded chunked buffering.
It uses the segmented storage family from `containers-d`, acquires independent
fixed-size chunks up to a maximum, exposes borrowed `chunks` without
flattening, and retains acquired capacity across `reset()`.

```d
auto received = new SegmentedByteBuffer(64 * 1024, 16 * 1024 * 1024);
auto result = received.append(httpChunk);
if (result.ok)
{
    foreach (chunk; received.chunks)
        uploadChunk(chunk);
}
received.reset();
```

The outer `chunks` view is a short-lived observation list; the byte slices
borrow the buffer and must not outlive it or a structural mutation. The
consumer-facing names intentionally describe data flow (`chunks`,
`chunkCount`, `maximumBytes`) rather than storage implementation details.
The extraction history remains in `docs/CONTAINERS_D_PROPOSAL.md`.

Concrete sources expose lightweight provenance through `provenance`, carrying
an identifier and scheme. This describes the origin only; authentication
credentials and request headers are never part of the provenance value.

`ObservedSource` decorates any source with request count, requested bytes,
returned bytes, largest range and last error. It is intended for consumer
probes and measurements, not as a cache or scheduler.

The asynchronous boundary is available through `AsyncByteSource`,
`AsyncExecutor`, `AsyncOperation` and `AsyncSourceAdapter`. The caller owns
the executor and the destination buffer until the callback returns.

## Development

```sh
dub test --compiler=dmd
dub test --compiler=ldc2
tools/http_integration.sh
```
