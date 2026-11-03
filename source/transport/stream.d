module transport.stream;

import transport.source : ByteRange, ByteSink, ByteSource, ReadError, ReadResult,
    TransferError, TransferLimits, TransferResult, WriteError, WriteResult;

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
            return ReadResult(ReadError.endOfSource, 0);
        auto result = source.readSome(offset, destination);
        if (result.bytesRead > 0)
            offset += result.bytesRead;
        return result;
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
        return TransferResult(TransferError.limitExceeded, 0);
    auto buffer = new ubyte[limits.chunkSize];
    size_t transferred;
    while (transferred < limits.maximumBytes)
    {
        auto length = limits.maximumBytes - transferred;
        if (length > buffer.length) length = buffer.length;
        auto read = reader.read(buffer[0 .. length]);
        if (read.error == ReadError.endOfSource)
            break;
        if (!read.ok)
            return TransferResult(TransferError.sourceFailure, transferred);
        if (read.bytesRead == 0)
            return TransferResult(TransferError.sourceFailure, transferred);
        auto written = writer.write(buffer[0 .. read.bytesRead]);
        if (!written.ok)
            return TransferResult(TransferError.destinationFailure, transferred);
        transferred += written.bytesWritten;
        if (written.bytesWritten != read.bytesRead)
            return TransferResult(TransferError.destinationFailure, transferred);
    }
    return TransferResult(TransferError.none, transferred);
}
