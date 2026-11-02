module transport.observe;

import transport.source : ByteRange, ByteSource, ReadError, ReadLimits,
    ReadResult;

/// Read-side evidence collected without changing source semantics.
struct ReadMetrics
{
    ulong requests;
    ulong bytesRead;
    ulong requestedBytes;
    size_t largestRequest;
    ReadError lastError;
}

/// Decorates a source with range, byte and error counters for consumer probes.
class ObservedSource : ByteSource
{
    private ByteSource source;
    private ReadMetrics metrics;

    this(ByteSource source) @safe
    {
        this.source = source;
    }

    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        ++metrics.requests;
        metrics.requestedBytes += range.length;
        if (range.length > metrics.largestRequest)
            metrics.largestRequest = range.length;
        auto result = source.read(range, destination, limits);
        metrics.bytesRead += result.bytesRead;
        metrics.lastError = result.error;
        return result;
    }

    @property ReadMetrics report() const @safe pure nothrow { return metrics; }
}
