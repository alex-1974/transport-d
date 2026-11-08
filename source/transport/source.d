module transport.source;

import std.stdio : File, SEEK_END, SEEK_SET;
import error_d : Result;

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
    bool lengthKnown;
    ulong length;
    bool rangeCapable;
}
struct ReadLimits { size_t maximumBytes = size_t.max; }
enum ReadError { none, endOfSource, invalidRange, rangeUnavailable, destinationTooSmall, limitExceeded, sourceFailure }
struct ReadValue { size_t bytesRead; }
struct ReadFailure { ReadError kind; size_t bytesRead; }
alias ReadResult = Result!(ReadValue, ReadFailure);
private ReadResult readSuccess(size_t bytes) @safe { return ReadResult.success(ReadValue(bytes)); }
private ReadResult readFailure(ReadError error, size_t bytes = 0) @safe
{
    return ReadResult.failure(ReadFailure(error, bytes));
}

interface ByteSource
{
    @property SourceInfo sourceInfo() const @safe;
    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe;

    /// Reads up to destination.length bytes. A short successful read means
    /// that the source ended at the returned byte count; the following call
    /// at that absolute offset returns endOfSource.
    ReadResult readSome(ulong offset, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe;
}

struct WriteLimits { size_t maximumBytes = size_t.max; }
enum WriteError { none, destinationFailure, limitExceeded }
struct WriteValue { size_t bytesWritten; }
struct WriteFailure { WriteError kind; size_t bytesWritten; }
alias WriteResult = Result!(WriteValue, WriteFailure);
private WriteResult writeSuccess(size_t bytes) @safe { return WriteResult.success(WriteValue(bytes)); }
private WriteResult writeFailure(WriteError error, size_t bytes = 0) @safe
{
    return WriteResult.failure(WriteFailure(error, bytes));
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
struct TransferValue { size_t bytesTransferred; }
struct TransferFailure { TransferError kind; size_t bytesTransferred; }
alias TransferResult = Result!(TransferValue, TransferFailure);
private TransferResult transferSuccess(size_t bytes) @safe { return TransferResult.success(TransferValue(bytes)); }
private TransferResult transferFailure(TransferError error, size_t bytes = 0) @safe
{
    return TransferResult.failure(TransferFailure(error, bytes));
}

class MemorySource : ByteSource
{
    private const(ubyte)[] bytes;
    this(scope const(ubyte)[] bytes) @safe { this.bytes = bytes; }
    @property SourceInfo provenance() const @safe pure nothrow
    {
        return SourceInfo("memory", "memory");
    }

    @property SourceInfo sourceInfo() const @safe pure nothrow
    {
        return SourceInfo("memory", "memory", true, bytes.length, true);
    }
    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (!range.valid)
            return readFailure(ReadError.invalidRange);
        if (range.offset == bytes.length)
            return readFailure(ReadError.endOfSource);
        if (range.offset > bytes.length
            || range.length > bytes.length - cast(size_t)range.offset)
            return readFailure(ReadError.invalidRange);
        if (range.length > limits.maximumBytes)
            return readFailure(ReadError.limitExceeded);
        if (destination.length < range.length)
            return readFailure(ReadError.destinationTooSmall);
        destination[0 .. range.length] = bytes[cast(size_t)range.offset ..
            cast(size_t)range.offset + range.length];
        return readSuccess(range.length);
    }

    ReadResult readSome(ulong offset, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (destination.length > limits.maximumBytes)
            return readFailure(ReadError.limitExceeded);
        if (offset > bytes.length)
            return readFailure(ReadError.invalidRange);
        if (offset == bytes.length)
            return readFailure(ReadError.endOfSource);
        auto count = bytes.length - cast(size_t) offset;
        if (count > destination.length) count = destination.length;
        destination[0 .. count] = bytes[cast(size_t) offset .. cast(size_t) offset + count];
        return readSuccess(count);
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

    @property SourceInfo sourceInfo() const @safe
    {
        try
        {
            auto file = File(path, "rb");
            scope (exit) file.close();
            file.seek(0, SEEK_END);
            return SourceInfo(path, "file", true, cast(ulong) file.tell(), true);
        }
        catch (Exception)
            return SourceInfo(path, "file", false, 0, true);
    }

    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (!range.valid) return readFailure(ReadError.invalidRange);
        if (range.length > limits.maximumBytes)
            return readFailure(ReadError.limitExceeded);
        if (destination.length < range.length)
            return readFailure(ReadError.destinationTooSmall);
        try
        {
            auto file = File(path, "rb");
            scope (exit) file.close();
            file.seek(0, SEEK_END);
            auto size = file.tell();
            if (range.offset == cast(ulong) size)
                return readFailure(ReadError.endOfSource);
            if (range.offset > cast(ulong) size
                || range.length > cast(ulong) size - range.offset)
                return readFailure(ReadError.invalidRange);
            file.seek(cast(long) range.offset, SEEK_SET);
            auto read = file.rawRead(destination[0 .. range.length]);
            if (read.length != range.length)
                return readFailure(ReadError.rangeUnavailable, read.length);
            return readSuccess(read.length);
        }
        catch (Exception) return readFailure(ReadError.sourceFailure);
    }

    ReadResult readSome(ulong offset, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (destination.length > limits.maximumBytes)
            return readFailure(ReadError.limitExceeded);
        if (destination.length == 0)
            return readFailure(ReadError.endOfSource);
        try
        {
            auto file = File(path, "rb");
            scope (exit) file.close();
            file.seek(0, SEEK_END);
            auto size = file.tell();
            if (offset == cast(ulong) size)
                return readFailure(ReadError.endOfSource);
            if (offset > cast(ulong) size)
                return readFailure(ReadError.invalidRange);
            auto count = cast(size_t)(cast(ulong) size - offset);
            if (count > destination.length) count = destination.length;
            file.seek(cast(long) offset, SEEK_SET);
            auto read = file.rawRead(destination[0 .. count]);
            return read.length == count
                ? readSuccess(count)
                : readFailure(ReadError.rangeUnavailable, read.length);
        }
        catch (Exception) return readFailure(ReadError.sourceFailure);
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
            return writeFailure(WriteError.limitExceeded);
        bytes ~= source;
        return writeSuccess(source.length);
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
            return writeFailure(WriteError.destinationFailure);
        if (source.length > limits.maximumBytes)
            return writeFailure(WriteError.limitExceeded);
        try
        {
            if (!opened)
            {
                file = File(path, append ? "ab" : "wb");
                opened = true;
            }
            file.rawWrite(source);
            return writeSuccess(source.length);
        }
        catch (Exception) return writeFailure(WriteError.destinationFailure);
    }
}

TransferResult copyTo(ByteSource source, ByteSink sink,
    TransferLimits limits = TransferLimits.init) @safe
{
    if (limits.chunkSize == 0)
        return transferFailure(TransferError.limitExceeded);
    auto buffer = new ubyte[limits.chunkSize];
    size_t offset;
    while (offset < limits.maximumBytes)
    {
        auto length = limits.maximumBytes - offset;
        if (length > buffer.length) length = buffer.length;
        auto read = source.readSome(offset, buffer[0 .. length]);
        if (read.hasError && read.error.kind == ReadError.endOfSource)
            break;
        if (!read.hasValue)
            return transferFailure(read.error.kind == ReadError.limitExceeded
                ? TransferError.limitExceeded : TransferError.sourceFailure, offset);
        auto written = sink.write(buffer[0 .. read.value.bytesRead]);
        if (!written.hasValue)
            return transferFailure(written.error.kind == WriteError.limitExceeded
                ? TransferError.limitExceeded : TransferError.destinationFailure, offset);
        offset += written.value.bytesWritten;
        if (read.value.bytesRead < length) break;
    }
    return transferSuccess(offset);
}
