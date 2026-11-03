module transport.http_curl;

import std.process : execute;
import std.process : Config;
import std.conv : to;
import transport.source : ByteSource, ByteRange, ReadLimits, ReadResult, ReadError, SourceInfo;

/// Research adapter: uses the system curl executable. It is intentionally
/// separate from the transport contract so a native HTTP implementation can
/// replace it without changing consumers.
class CurlHttpSource : ByteSource
{
    private string url;
    this(string url) @safe { this.url = url; }

    @property SourceInfo sourceInfo() const @safe pure nothrow
    {
        return SourceInfo(url, "http", false, 0, true);
    }

    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (!range.length || range.length > limits.maximumBytes
            || destination.length < range.length)
            return ReadResult(range.length > limits.maximumBytes
                ? ReadError.limitExceeded : ReadError.destinationTooSmall, 0);
        const end = range.offset + range.length - 1;
        try
        {
            auto result = execute(["curl", "--fail", "--silent", "--show-error",
                "--location", "--range", range.offset.to!string ~ "-" ~ end.to!string, url],
                null, Config.none, range.length + 1);
            if (result.status != 0 || result.output.length != range.length)
                return ReadResult(ReadError.rangeUnavailable, 0);
            destination[] = cast(const(ubyte)[])result.output[];
            return ReadResult(ReadError.none, range.length);
        }
        catch (Exception)
            return ReadResult(ReadError.sourceFailure, 0);
    }

    ReadResult readSome(ulong offset, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (destination.length > limits.maximumBytes)
            return ReadResult(ReadError.limitExceeded, 0);
        if (!destination.length) return ReadResult(ReadError.endOfSource, 0);
        auto end = offset + destination.length - 1;
        try
        {
            auto result = execute(["curl", "--fail", "--silent", "--show-error",
                "--location", "--range", offset.to!string ~ "-" ~ end.to!string, url],
                null, Config.none, destination.length + 1);
            if (result.status != 0)
                return ReadResult(ReadError.sourceFailure, 0);
            auto count = result.output.length;
            if (!count) return ReadResult(ReadError.endOfSource, 0);
            if (count > destination.length) count = destination.length;
            destination[0 .. count] = cast(const(ubyte)[])result.output[0 .. count];
            return ReadResult(ReadError.none, count);
        }
        catch (Exception) return ReadResult(ReadError.sourceFailure, 0);
    }
}
