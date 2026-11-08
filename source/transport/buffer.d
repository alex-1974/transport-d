module transport.buffer;

import containers : ContainerSegmentedByteBuffer = SegmentedByteBuffer;
import transport.source : ByteSink, WriteError, WriteFailure, WriteLimits,
    WriteResult, WriteValue;

/**
 * Reusable, bounded byte storage for chunked transport data.
 *
 * `SegmentedByteBuffer` keeps received data in independently owned chunks.
 * Appending may acquire another chunk, but never relocates earlier bytes.
 * Consumers can process `chunks` directly and avoid flattening the logical
 * payload into one allocation.
 *
 * The transport wrapper owns the transfer result and limit semantics. The
 * storage and element-lifetime implementation is supplied by containers-d.
 */
class SegmentedByteBuffer : ByteSink
{
    private ContainerSegmentedByteBuffer buffer;
    private size_t chunkSize;
    private size_t maximumSize;

    /**
     * Creates an empty chunk buffer.
     *
     * Params:
     *   chunkSize = maximum number of bytes in each independently owned chunk;
     *   maximumBytes = maximum logical payload size accepted by this buffer.
     *
     * Throws: `Exception` when `chunkSize` is zero.
     */
    this(size_t chunkSize, size_t maximumBytes = size_t.max) @safe
    {
        if (chunkSize == 0)
            throw new Exception("chunkSize must be greater than zero");
        this.chunkSize = chunkSize;
        this.maximumSize = maximumBytes;
        buffer = ContainerSegmentedByteBuffer(chunkSize, maximumBytes);
    }

    /// Number of bytes currently retained.
    @property size_t length() const @safe pure nothrow { return buffer.length; }

    /// Maximum number of bytes accepted by this buffer.
    @property size_t maximumBytes() const @safe pure nothrow
    {
        return maximumSize;
    }

    /// Number of chunks acquired for this buffer.
    @property size_t chunkCount() const @safe pure nothrow
    {
        return buffer.segmentCount;
    }

    /// Bytes reserved in acquired chunks. Reset retains this capacity.
    @property size_t capacity() const @safe pure nothrow
    {
        return buffer.segmentCount * chunkSize;
    }

    /**
     * Borrows the logical payload as ordered chunks.
     *
     * The returned outer array is a view list allocated for this observation;
     * its byte slices borrow the buffer. Structural mutation, consumption,
     * reset and destruction invalidate the returned byte slices.
     */
    @property const(ubyte)[][] chunks() const @safe
    {
        auto result = new const(ubyte)[][](buffer.segmentCount);
        foreach (i; 0 .. buffer.segmentCount)
            result[i] = buffer.segment(i);
        return result;
    }

    /**
     * Appends one received chunk atomically with respect to the configured
     * maximum. No bytes are accepted when the complete input would exceed a
     * limit.
     */
    WriteResult append(scope const(ubyte)[] source,
        WriteLimits limits = WriteLimits.init) @safe
    {
        if (source.length > limits.maximumBytes)
            return WriteResult.failure(WriteFailure(WriteError.limitExceeded, 0));
        if (source.length > maximumSize - buffer.length)
            return WriteResult.failure(WriteFailure(WriteError.limitExceeded, 0));
        const accepted = buffer.append(source);
        return accepted == source.length
            ? WriteResult.success(WriteValue(accepted))
            : WriteResult.failure(WriteFailure(WriteError.destinationFailure, accepted));
    }

    WriteResult write(scope const(ubyte)[] source,
        WriteLimits limits = WriteLimits.init) @safe
    {
        return append(source, limits);
    }

    /** Clear logical contents while retaining all acquired chunk capacity. */
    void reset() @safe
    {
        buffer.reset();
    }
}
