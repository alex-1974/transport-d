module transport.source;

import std.file : readFile = read;

struct ByteRange { ulong offset; size_t length; }
struct ReadLimits { size_t maximumBytes = size_t.max; }
enum ReadError { none, invalidRange, rangeUnavailable, destinationTooSmall, limitExceeded, sourceFailure }
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

class MemorySource : ByteSource
{
    private const(ubyte)[] bytes;
    this(scope const(ubyte)[] bytes) @safe { this.bytes = bytes; }
    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (range.length == 0 || range.offset > bytes.length
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
    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (range.length == 0) return ReadResult(ReadError.invalidRange, 0);
        if (range.length > limits.maximumBytes)
            return ReadResult(ReadError.limitExceeded, 0);
        if (destination.length < range.length)
            return ReadResult(ReadError.destinationTooSmall, 0);
        const(ubyte)[] bytes;
        try bytes = cast(const(ubyte)[]) readFile(path);
        catch (Exception) return ReadResult(ReadError.sourceFailure, 0);
        if (range.offset > bytes.length || range.length > bytes.length - cast(size_t)range.offset)
            return ReadResult(ReadError.invalidRange, 0);
        destination[0 .. range.length] = bytes[cast(size_t)range.offset ..
            cast(size_t)range.offset + range.length];
        return ReadResult(ReadError.none, range.length);
    }
}
