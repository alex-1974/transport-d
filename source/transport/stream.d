module transport.stream;

import std.stdio : File, SEEK_END, SEEK_SET;
import transport.source : ByteRange, ByteSink, ByteSource, ReadError, ReadFailure,
    ReadResult, ReadValue, TransferError, TransferFailure, TransferLimits,
    TransferResult, TransferValue, WriteError, WriteFailure, WriteResult,
    WriteValue;

interface ByteReader
{
    ReadResult read(scope ubyte[] destination) @safe;
}

interface ByteWriter
{
    WriteResult write(scope const(ubyte)[] source) @safe;
}

class SourceReader : ByteReader
{
    private ByteSource source;
    private ulong offset;

    this(ByteSource source, ulong offset = 0) @safe
    {
        this.source = source;
        this.offset = offset;
    }

    @property ulong position() const @safe pure nothrow { return offset; }

    ReadResult read(scope ubyte[] destination) @safe
    {
        if (destination.length == 0)
            return ReadResult.failure(ReadFailure(ReadError.endOfSource, 0));
        auto result = source.readSome(offset, destination);
        if (result.hasValue)
            offset += result.value.bytesRead;
        return result;
    }
}

/// Persistent sequential reader for a local file. The handle is owned by this
/// session, so independent readers can safely use the same FileSource.
class FileReader : ByteReader
{
    private File file;
    private ulong offset;
    private ulong length;
    private bool closed;

    this(string path) @safe
    {
        file = File(path, "rb");
        file.seek(0, SEEK_END);
        length = cast(ulong) file.tell();
        file.seek(0, SEEK_SET);
    }

    ~this() @safe { close(); }

    @property ulong position() const @safe pure nothrow { return offset; }
    @property bool isClosed() const @safe pure nothrow { return closed; }

    void close() @safe nothrow
    {
        if (!closed)
        {
            try file.close();
            catch (Exception) { }
            closed = true;
        }
    }

    ReadResult read(scope ubyte[] destination) @safe
    {
        if (closed) return ReadResult.failure(ReadFailure(ReadError.sourceFailure, 0));
        if (!destination.length || offset == length)
            return ReadResult.failure(ReadFailure(ReadError.endOfSource, 0));
        if (offset > length) return ReadResult.failure(ReadFailure(ReadError.invalidRange, 0));
        auto count = destination.length;
        if (cast(ulong) count > length - offset)
            count = cast(size_t)(length - offset);
        try
        {
            auto received = file.rawRead(destination[0 .. count]);
            offset += received.length;
            return received.length == count
                ? ReadResult.success(ReadValue(received.length))
                : ReadResult.failure(ReadFailure(ReadError.rangeUnavailable, received.length));
        }
        catch (Exception) return ReadResult.failure(ReadFailure(ReadError.sourceFailure, 0));
    }
}

class SinkWriter : ByteWriter
{
    private ByteSink sink;

    this(ByteSink sink) @safe
    {
        this.sink = sink;
    }

    WriteResult write(scope const(ubyte)[] source) @safe
    {
        return sink.write(source);
    }
}

TransferResult copyTo(ByteReader reader, ByteWriter writer,
    TransferLimits limits = TransferLimits.init) @safe
{
    if (limits.chunkSize == 0)
        return TransferResult.failure(TransferFailure(TransferError.limitExceeded, 0));
    auto buffer = new ubyte[limits.chunkSize];
    size_t transferred;
    while (transferred < limits.maximumBytes)
    {
        auto length = limits.maximumBytes - transferred;
        if (length > buffer.length) length = buffer.length;
        auto read = reader.read(buffer[0 .. length]);
        if (read.hasError && read.error.kind == ReadError.endOfSource)
            break;
        if (!read.hasValue)
            return TransferResult.failure(TransferFailure(TransferError.sourceFailure, transferred));
        if (read.value.bytesRead == 0)
            return TransferResult.failure(TransferFailure(TransferError.sourceFailure, transferred));
        auto written = writer.write(buffer[0 .. read.value.bytesRead]);
        if (!written.hasValue)
            return TransferResult.failure(TransferFailure(TransferError.destinationFailure, transferred));
        transferred += written.value.bytesWritten;
        if (written.value.bytesWritten != read.value.bytesRead)
            return TransferResult.failure(TransferFailure(TransferError.destinationFailure, transferred));
    }
    return TransferResult.success(TransferValue(transferred));
}
