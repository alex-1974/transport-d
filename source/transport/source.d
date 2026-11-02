module transport.source;

import std.stdio : File, SEEK_END, SEEK_SET;

struct ByteRange { ulong offset; size_t length; }
@property bool valid(ByteRange range) @safe pure nothrow
{
    return range.length != 0
        && cast(ulong) range.length - 1 <= ulong.max - range.offset;
}
struct SourceInfo
{
    string identifier;
    string scheme;
}
struct ReadLimits { size_t maximumBytes = size_t.max; }
enum ReadError { none, endOfSource, invalidRange, rangeUnavailable, destinationTooSmall, limitExceeded, sourceFailure }
struct ReadResult
{
    ReadError error;
    size_t bytesRead;
    @property bool ok() const @safe pure nothrow @nogc { return error == ReadError.none; }
}

interface ByteSource
{
    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe;
}

struct WriteLimits { size_t maximumBytes = size_t.max; }
enum WriteError { none, destinationFailure, limitExceeded }
struct WriteResult
{
    WriteError error;
    size_t bytesWritten;
    @property bool ok() const @safe pure nothrow @nogc { return error == WriteError.none; }
}

interface ByteSink
{
    WriteResult write(scope const(ubyte)[] source,
        WriteLimits limits = WriteLimits.init) @safe;
}

struct TransferLimits
{
    size_t maximumBytes = size_t.max;
    size_t chunkSize = 64 * 1024;
}

enum TransferError { none, sourceFailure, destinationFailure, limitExceeded }
struct TransferResult
{
    TransferError error;
    size_t bytesTransferred;
    @property bool ok() const @safe pure nothrow @nogc { return error == TransferError.none; }
}

class MemorySource : ByteSource
{
    private const(ubyte)[] bytes;
    this(scope const(ubyte)[] bytes) @safe { this.bytes = bytes; }
    @property SourceInfo provenance() const @safe pure nothrow
    {
        return SourceInfo("memory", "memory");
    }
    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (!range.valid)
            return ReadResult(ReadError.invalidRange, 0);
        if (range.offset == bytes.length)
            return ReadResult(ReadError.endOfSource, 0);
        if (range.offset > bytes.length
            || range.length > bytes.length - cast(size_t)range.offset)
            return ReadResult(ReadError.invalidRange, 0);
        if (range.length > limits.maximumBytes)
            return ReadResult(ReadError.limitExceeded, 0);
        if (destination.length < range.length)
            return ReadResult(ReadError.destinationTooSmall, 0);
        destination[0 .. range.length] = bytes[cast(size_t)range.offset ..
            cast(size_t)range.offset + range.length];
        return ReadResult(ReadError.none, range.length);
    }
}

class FileSource : ByteSource
{
    private string path;
    this(string path) @safe { this.path = path; }
    @property SourceInfo provenance() const @safe pure nothrow
    {
        return SourceInfo(path, "file");
    }
    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (!range.valid) return ReadResult(ReadError.invalidRange, 0);
        if (range.length > limits.maximumBytes)
            return ReadResult(ReadError.limitExceeded, 0);
        if (destination.length < range.length)
            return ReadResult(ReadError.destinationTooSmall, 0);
        try
        {
            auto file = File(path, "rb");
            scope (exit) file.close();
            file.seek(0, SEEK_END);
            auto size = file.tell();
            if (range.offset == cast(ulong) size)
                return ReadResult(ReadError.endOfSource, 0);
            if (range.offset > cast(ulong) size
                || range.length > cast(ulong) size - range.offset)
                return ReadResult(ReadError.invalidRange, 0);
            file.seek(cast(long) range.offset, SEEK_SET);
            auto read = file.rawRead(destination[0 .. range.length]);
            if (read.length != range.length)
                return ReadResult(ReadError.rangeUnavailable, read.length);
            return ReadResult(ReadError.none, read.length);
        }
        catch (Exception) return ReadResult(ReadError.sourceFailure, 0);
    }
}

class MemorySink : ByteSink
{
    private ubyte[] bytes;
    @property const(ubyte)[] data() const @safe pure nothrow { return bytes; }
    WriteResult write(scope const(ubyte)[] source,
        WriteLimits limits = WriteLimits.init) @safe
    {
        if (source.length > limits.maximumBytes)
            return WriteResult(WriteError.limitExceeded, 0);
        bytes ~= source;
        return WriteResult(WriteError.none, source.length);
    }
}

class FileSink : ByteSink
{
    private string path;
    private bool append;
    private bool opened;
    private bool closed;
    private File file;

    this(string path, bool append = false) @safe
    {
        this.path = path;
        this.append = append;
    }

    ~this() @safe
    {
        close();
    }

    @property bool isOpen() const @safe pure nothrow { return opened && !closed; }

    void close() @safe nothrow
    {
        if (opened && !closed)
        {
            try file.close();
            catch (Exception) { }
        }
        closed = true;
    }

    WriteResult write(scope const(ubyte)[] source,
        WriteLimits limits = WriteLimits.init) @safe
    {
        if (closed)
            return WriteResult(WriteError.destinationFailure, 0);
        if (source.length > limits.maximumBytes)
            return WriteResult(WriteError.limitExceeded, 0);
        try
        {
            if (!opened)
            {
                file = File(path, append ? "ab" : "wb");
                opened = true;
            }
            file.rawWrite(source);
            return WriteResult(WriteError.none, source.length);
        }
        catch (Exception) return WriteResult(WriteError.destinationFailure, 0);
    }
}

TransferResult copyTo(ByteSource source, ByteSink sink,
    TransferLimits limits = TransferLimits.init) @safe
{
    if (limits.chunkSize == 0)
        return TransferResult(TransferError.limitExceeded, 0);
    auto buffer = new ubyte[limits.chunkSize];
    size_t offset;
    while (offset < limits.maximumBytes)
    {
        auto length = limits.maximumBytes - offset;
        if (length > buffer.length) length = buffer.length;
        auto read = source.read(ByteRange(offset, length), buffer[]);
        if (read.error == ReadError.endOfSource)
            break;
        if (!read.ok)
            return TransferResult(read.error == ReadError.limitExceeded
                ? TransferError.limitExceeded : TransferError.sourceFailure, offset);
        auto written = sink.write(buffer[0 .. read.bytesRead]);
        if (!written.ok)
            return TransferResult(written.error == WriteError.limitExceeded
                ? TransferError.limitExceeded : TransferError.destinationFailure, offset);
        offset += written.bytesWritten;
        if (read.bytesRead < length) break;
    }
    return TransferResult(TransferError.none, offset);
}
