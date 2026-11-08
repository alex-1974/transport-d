module transport.observe;

import transport.source : ByteRange, ByteSource, ReadError, ReadLimits,
    ReadResult, SourceInfo;

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

    @property SourceInfo sourceInfo() const @safe
    {
        return source.sourceInfo;
    }

    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        ++metrics.requests;
        metrics.requestedBytes += range.length;
        if (range.length > metrics.largestRequest)
            metrics.largestRequest = range.length;
        auto result = source.read(range, destination, limits);
        if (result.hasValue)
            metrics.bytesRead += result.value.bytesRead;
        else
            metrics.lastError = result.error.kind;
        return result;
    }

    ReadResult readSome(ulong offset, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        ++metrics.requests;
        metrics.requestedBytes += destination.length;
        if (destination.length > metrics.largestRequest)
            metrics.largestRequest = destination.length;
        auto result = source.readSome(offset, destination, limits);
        if (result.hasValue)
            metrics.bytesRead += result.value.bytesRead;
        else
            metrics.lastError = result.error.kind;
        return result;
    }

    @property ReadMetrics report() const @safe pure nothrow { return metrics; }
}
