# SegmentedByteBuffer for transport consumers

`SegmentedByteBuffer` collects received bytes without forcing them into one
large contiguous allocation. This is useful when an HTTP response, range read,
or upload is naturally delivered in chunks.

## Typical use

```d
import transport;

auto received = new SegmentedByteBuffer(64 * 1024, 16 * 1024 * 1024);

WriteResult accepted = received.append(receivedBytes);
if (!accepted.ok)
    return handleLimitFailure();

foreach (chunk; received.chunks)
    consumeChunk(chunk);

received.reset();
```

## Public vocabulary

- `chunkSize`: maximum size of one acquired chunk;
- `maximumBytes`: maximum logical payload accepted;
- `length`: bytes currently retained;
- `capacity`: bytes reserved in acquired chunks;
- `chunkCount`: number of acquired chunks;
- `chunks`: ordered borrowed byte chunks;
- `append`: accept a complete input chunk or reject it without partial input;
- `reset`: clear logical contents while retaining acquired capacity.

These names describe what a transport consumer does. Allocation and raw-storage
terminology remains internal to `containers-d`.

## Bounds and failure

`append` checks both `WriteLimits.maximumBytes` and the buffer's
`maximumBytes`. If either limit would be exceeded, it returns
`WriteError.limitExceeded` and accepts no bytes. A successful append reports
the full source length in `bytesWritten`.

The buffer never silently flattens, grows beyond its maximum, or overwrites
existing bytes.

## Borrowing

`chunks` returns an ordered observation list. The list itself is newly created;
the byte slices borrow the buffer. Do not retain them across `append`, `reset`,
owner destruction, or any future consuming operation.

Acquiring a later chunk does not relocate earlier chunk storage, but the
conservative consumer contract still treats all borrowed views as invalid after
structural mutation.

## Reuse

`reset` ends the logical payload but keeps acquired capacity. Reusing one
buffer for repeated HTTP ranges avoids repeated segment allocation while
preserving the configured memory bound.
