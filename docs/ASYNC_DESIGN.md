# Asynchronous extension design

The API now includes a scheduler-neutral asynchronous source boundary. It
retains the same source vocabulary and result values:

```text
ByteSource.read       -> AsyncByteSource.readAsync
ByteSink.write        -> future AsyncByteSink.writeAsync
copyTo                -> future asyncCopyTo
```

The asynchronous boundary does not introduce a scheduler, thread pool or
cache into `transport-d`. A caller supplies the execution mechanism, and an
operation owns its buffers until completion. Cancellation and timeout are
operation properties, not global state. `InlineExecutor` provides a
deterministic integration/test executor; a real threaded or event-loop
executor belongs to the caller or a later backend module.

No `Future` type or background thread is hidden in the public API. A concrete
executor must document buffer lifetime, callback thread, cancellation race and
error-delivery behavior before being admitted as a production backend.
