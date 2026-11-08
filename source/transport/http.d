module transport.http;

import std.format : format;
import std.algorithm.comparison : min;
import std.string : split, strip;
import std.conv : to;
import core.time : Duration;
import std.net.curl : HTTP;
import transport.buffer : SegmentedByteBuffer;
import transport.source : ByteRange, ByteSink, ByteSource, ReadError,
    ReadFailure, ReadLimits, ReadResult, ReadValue, SourceInfo, TransferError,
    TransferFailure, TransferLimits, TransferResult, TransferValue, WriteError,
    WriteFailure, WriteLimits, WriteResult, WriteValue, copyTo, valid;

struct HttpOptions
{
    Duration timeout;
    Duration connectTimeout;
    uint maxRedirects;
    string userAgent;
}

struct HttpResponseInfo
{
    ushort statusCode;
    ulong contentLength;
    string contentRange;
    string effectiveUrl;
    ulong totalLength = ulong.max;
}

/// Synchronous HTTP byte-range source.
class HttpSource : ByteSource
{
    private string url;
    private HttpOptions options;
    private HttpResponseInfo response;

    this(string url, HttpOptions options = HttpOptions.init) @safe
    {
        this.url = url;
        this.options = options;
    }

    @property HttpResponseInfo responseInfo() const @safe pure nothrow { return response; }

    @property SourceInfo provenance() const @safe pure nothrow
    {
        return SourceInfo(url, "http");
    }

    @property SourceInfo sourceInfo() const @safe pure nothrow
    {
        return SourceInfo(url, "http", response.totalLength != ulong.max,
            response.totalLength == ulong.max ? 0 : response.totalLength,
            true);
    }

    ReadResult read(ByteRange range, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @trusted
    {
        if (!valid(range))
            return ReadResult.failure(ReadFailure(ReadError.invalidRange, 0));
        if (range.length > limits.maximumBytes)
            return ReadResult.failure(ReadFailure(ReadError.limitExceeded, 0));
        if (destination.length < range.length)
            return ReadResult.failure(ReadFailure(ReadError.destinationTooSmall, 0));

        try
        {
            auto client = HTTP(url);
            if (options.timeout > Duration.zero) client.operationTimeout = options.timeout;
            if (options.connectTimeout > Duration.zero) client.connectTimeout = options.connectTimeout;
            client.maxRedirects = options.maxRedirects;
            if (options.userAgent.length) client.setUserAgent(options.userAgent);
            client.addRequestHeader("Range",
                format("bytes=%s-%s", range.offset,
                    range.offset + range.length - 1));
            auto responseBuffer = new SegmentedByteBuffer(
                range.length < 64 * 1024 ? range.length : 64 * 1024,
                range.length);
            HTTP.StatusLine status;
            string contentRange;
            ulong contentLength = ulong.max;
            client.onReceiveStatusLine = (HTTP.StatusLine line) { status = line; };
            client.onReceiveHeader = (in char[] key, in char[] value)
            {
                if (key == "content-range") contentRange = value.idup;
                if (key == "content-length")
                {
                    import std.conv : to;
                    contentLength = value.to!ulong;
                }
            };
            client.onReceive = (ubyte[] data)
            {
                auto result = responseBuffer.write(data);
                return result.hasValue ? data.length : 0;
            };
            client.perform();
            auto totalLength = parseTotalLength(contentRange);
            response = HttpResponseInfo(status.code, contentLength, contentRange, url,
                totalLength);
            if (status.code / 100 != 2)
                return ReadResult.failure(ReadFailure(ReadError.sourceFailure, 0));
            if (status.code == 206 && (!contentRange.length
                || !validContentRange(contentRange, range.offset,
                    responseBuffer.length, totalLength)))
                return ReadResult.failure(ReadFailure(ReadError.rangeUnavailable, 0));
            size_t offset;
            foreach (segment; responseBuffer.chunks)
            {
                destination[offset .. offset + segment.length] = segment[];
                offset += segment.length;
            }
            if (responseBuffer.length != range.length)
                return ReadResult.failure(ReadFailure(ReadError.rangeUnavailable, responseBuffer.length));
            return ReadResult.success(ReadValue(offset));
        }
        catch (Exception)
            return ReadResult.failure(ReadFailure(ReadError.sourceFailure, 0));
    }

    ReadResult readSome(ulong offset, scope ubyte[] destination,
        ReadLimits limits = ReadLimits.init) @safe
    {
        if (!destination.length)
            return ReadResult.failure(ReadFailure(ReadError.endOfSource, 0));
        auto result = read(ByteRange(offset, destination.length), destination, limits);
        if (result.hasError && result.error.kind == ReadError.rangeUnavailable && result.error.bytesRead > 0)
            return ReadResult.success(ReadValue(result.error.bytesRead));
        if (result.hasError && result.error.kind == ReadError.sourceFailure && response.statusCode == 416)
        {
            if (response.totalLength != ulong.max && offset == response.totalLength)
                return ReadResult.failure(ReadFailure(ReadError.endOfSource, 0));
            if (response.totalLength != ulong.max && offset > response.totalLength)
                return ReadResult.failure(ReadFailure(ReadError.invalidRange, 0));
        }
        if (result.hasError && result.error.kind == ReadError.rangeUnavailable && result.error.bytesRead == 0)
            return ReadResult.failure(ReadFailure(ReadError.sourceFailure, 0));
        return result;
    }
}

private ulong parseTotalLength(string value) @safe pure nothrow
{
    auto fields = value.strip.split("/");
    if (fields.length != 2 || fields[1] == "*") return ulong.max;
    try return fields[1].to!ulong;
    catch (Exception) return ulong.max;
}

private bool validContentRange(string value, ulong offset, size_t bodyLength,
    ulong totalLength) @safe pure nothrow
{
    auto fields = value.strip.split("/");
    if (fields.length != 2 || fields[0].strip.split(" ").length != 2)
        return false;
    auto range = fields[0].strip.split(" ")[1].split("-");
    if (range.length != 2) return false;
    try
    {
        auto start = range[0].to!ulong;
        auto end = range[1].to!ulong;
        return start == offset && end >= start && end - start + 1 == bodyLength
            && (totalLength == ulong.max || end < totalLength);
    }
    catch (Exception) return false;
}

/// Buffered synchronous HTTP upload destination.
///
/// Bytes are sent once, when close() is called. This keeps the ByteSink
/// contract useful for chunked producers without pretending that each write
/// is an independent HTTP request.
class HttpSink : ByteSink
{
    private string url;
    private HttpOptions options;
    private SegmentedByteBuffer payload;
    private bool closed;
    private TransferResult transfer;

    this(string url, size_t segmentSize = 64 * 1024,
        size_t maximumBytes = 64 * 1024 * 1024,
        HttpOptions options = HttpOptions.init) @safe
    {
        this.url = url;
        this.options = options;
        payload = new SegmentedByteBuffer(segmentSize, maximumBytes);
    }

    WriteResult write(scope const(ubyte)[] source,
        WriteLimits limits = WriteLimits.init) @safe
    {
        if (closed)
            return WriteResult.failure(WriteFailure(WriteError.destinationFailure, 0));
        if (source.length > limits.maximumBytes)
            return WriteResult.failure(WriteFailure(WriteError.limitExceeded, 0));
        return payload.write(source);
    }

    void close() @trusted
    {
        if (closed)
            return;
        closed = true;
        try
        {
            auto client = HTTP(url);
            if (options.timeout > Duration.zero) client.operationTimeout = options.timeout;
            if (options.connectTimeout > Duration.zero) client.connectTimeout = options.connectTimeout;
            client.maxRedirects = options.maxRedirects;
            if (options.userAgent.length) client.setUserAgent(options.userAgent);
            client.method = HTTP.Method.put;
            client.contentLength = payload.length;
            auto segments = payload.chunks;
            size_t segmentIndex;
            size_t segmentOffset;
            client.onSend = delegate size_t(void[] target)
            {
                auto output = cast(ubyte[]) target;
                size_t written;
                while (segmentIndex < segments.length && written < output.length)
                {
                    auto current = segments[segmentIndex];
                    auto count = min(output.length - written,
                        current.length - segmentOffset);
                    output[written .. written + count] =
                        current[segmentOffset .. segmentOffset + count];
                    written += count;
                    segmentOffset += count;
                    if (segmentOffset == current.length)
                    {
                        ++segmentIndex;
                        segmentOffset = 0;
                    }
                }
                return written;
            };
            HTTP.StatusLine status;
            client.onReceiveStatusLine = (HTTP.StatusLine line) { status = line; };
            client.onReceive = (ubyte[] data) { return data.length; };
            client.perform();
            if (status.code / 100 != 2)
                transfer = TransferResult.failure(TransferFailure(TransferError.destinationFailure, 0));
            else
                transfer = TransferResult.success(TransferValue(payload.length));
        }
        catch (Exception)
            transfer = TransferResult.failure(TransferFailure(TransferError.destinationFailure, 0));
    }

    @property bool isClosed() const @safe pure nothrow { return closed; }
    @property TransferResult result() const @safe pure nothrow { return transfer; }
}

TransferResult uploadTo(ByteSource source, string url,
    TransferLimits limits = TransferLimits.init) @safe
{
    auto sink = new HttpSink(url, limits.chunkSize, limits.maximumBytes);
    auto copied = copyTo(source, sink, limits);
    if (!copied.hasValue)
        return copied;
    sink.close();
    return sink.result;
}
