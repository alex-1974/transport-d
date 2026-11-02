module transport.http_curl;

import std.process : execute;
import std.process : Config;
import std.conv : to;
import transport.source : ByteSource, ByteRange, ReadLimits, ReadResult, ReadError;

/// Research adapter: uses the system curl executable. It is intentionally
/// separate from the transport contract so a native HTTP implementation can
/// replace it without changing consumers.
class CurlHttpSource : ByteSource
{
    private string url;
    this(string url) @safe { this.url = url; }

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
}
