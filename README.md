# transport-d

Shared byte-resource transport for `imageio-d`, `dunia` and other workspace
consumers.

Status: research-only initial package. The first slice defines one readable
range contract and local memory/file sources. HTTP, retries, cancellation and
cache policy require their own measured gate. This package does not parse
images, OSM data or raster semantics.

## Contract

```d
auto result = source.read(ByteRange(offset, length), destination[], limits);
```

The source reports the requested range, bytes returned and a structured error.
It must never silently replace a failed range read with a full-resource read.

## Development

```sh
dub test --compiler=dmd
dub test --compiler=ldc2
```
