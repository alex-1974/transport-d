module transport.exchange;

import core.time : Duration;
import std.net.curl : HTTP;
import error_d : Result;
import transport.buffer : SegmentedByteBuffer;

/// Request limits for a generic HTTP exchange.
struct HttpExchangeLimits
{
    size_t maximumRequestBytes = 64 * 1024 * 1024;
    size_t maximumResponseBytes = 16 * 1024 * 1024;
    size_t maximumResponseHeaders = 256;
}

struct HttpExchangeOptions
{
    Duration timeout;
    Duration connectTimeout;
    uint maxRedirects;
    string userAgent;
}

/// HTTP methods supported by the generic exchange.
enum HttpMethod { get, head, post, put, delete_, options, trace, connect, patch }

/// A bounded request body. The buffer is owned by the caller and must remain
/// alive until exchange() returns.
struct HttpRequest
{
    HttpMethod method = HttpMethod.get;
    string url;
    string[string] headers;
    string[string] sensitiveHeaders;
    SegmentedByteBuffer body;
    HttpExchangeLimits limits;
    HttpExchangeOptions options;
}

struct HttpResponse
{
    ushort statusCode;
    string reason;
    string[string] headers;
    string effectiveUrl;
    SegmentedByteBuffer body;
}

enum HttpExchangeErrorKind
{
    invalidRequest,
    requestLimitExceeded,
    responseLimitExceeded,
    responseHeaderLimitExceeded,
    setupFailure,
    transportFailure
}

/// Deliberately contains no backend exception text or request headers.
struct HttpExchangeError
{
    HttpExchangeErrorKind kind;
}

alias HttpExchangeResult = Result!(HttpResponse, HttpExchangeError);

interface HttpExchange
{
    HttpExchangeResult exchange(scope const ref HttpRequest request) @safe;
}

/// Native synchronous implementation backed by Phobos/libcurl.
final class CurlHttpExchange : HttpExchange
{
    HttpExchangeResult exchange(scope const ref HttpRequest request) @trusted
    {
        if (!request.url.length)
            return HttpExchangeResult.failure(HttpExchangeError(
                HttpExchangeErrorKind.invalidRequest));
        // Never let libcurl carry credentials across an unchecked redirect.
        // Callers can explicitly retry against a verified target URL.
        if (request.sensitiveHeaders.length && request.options.maxRedirects)
            return HttpExchangeResult.failure(HttpExchangeError(
                HttpExchangeErrorKind.invalidRequest));
        if (request.body !is null
            && request.body.length > request.limits.maximumRequestBytes)
            return HttpExchangeResult.failure(HttpExchangeError(
                HttpExchangeErrorKind.requestLimitExceeded));

        try
        {
            auto client = HTTP(request.url);
            if (request.options.timeout > Duration.zero)
                client.operationTimeout = request.options.timeout;
            if (request.options.connectTimeout > Duration.zero)
                client.connectTimeout = request.options.connectTimeout;
            client.maxRedirects = request.options.maxRedirects;
            if (request.options.userAgent.length)
                client.setUserAgent(request.options.userAgent);

            foreach (name, value; request.headers)
                client.addRequestHeader(name, value);
            foreach (name, value; request.sensitiveHeaders)
                client.addRequestHeader(name, value);

            client.method = toCurlMethod(request.method);
            if (request.body !is null)
            {
                client.contentLength = request.body.length;
                auto segments = request.body.chunks;
                size_t segmentIndex;
                size_t segmentOffset;
                client.onSend = delegate size_t(void[] target)
                {
                    auto output = cast(ubyte[]) target;
                    size_t written;
                    while (segmentIndex < segments.length && written < output.length)
                    {
                        auto current = segments[segmentIndex];
                        auto count = output.length - written;
                        if (count > current.length - segmentOffset)
                            count = current.length - segmentOffset;
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
            }

            auto responseBody = new SegmentedByteBuffer(64 * 1024,
                request.limits.maximumResponseBytes);
            size_t headerCount;
            bool responseLimit;
            bool headerLimit;
            client.onReceiveHeader = (in char[] name, in char[] value)
            {
                if (++headerCount > request.limits.maximumResponseHeaders)
                {
                    headerLimit = true;
                    return;
                }
            };
            client.onReceive = (ubyte[] data)
            {
                auto written = responseBody.append(data);
                if (!written.hasValue)
                {
                    responseLimit = true;
                    return 0;
                }
                return data.length;
            };
            client.perform();

            if (headerLimit)
                return HttpExchangeResult.failure(HttpExchangeError(
                    HttpExchangeErrorKind.responseHeaderLimitExceeded));
            if (responseLimit)
                return HttpExchangeResult.failure(HttpExchangeError(
                    HttpExchangeErrorKind.responseLimitExceeded));

            auto headers = client.responseHeaders;
            return HttpExchangeResult.success(HttpResponse(client.statusLine.code,
                client.statusLine.reason, headers, request.url, responseBody));
        }
        catch (Exception)
            return HttpExchangeResult.failure(HttpExchangeError(
                HttpExchangeErrorKind.transportFailure));
    }
}

private HTTP.Method toCurlMethod(HttpMethod method) @safe pure nothrow
{
    final switch (method)
    {
        case HttpMethod.get: return HTTP.Method.get;
        case HttpMethod.head: return HTTP.Method.head;
        case HttpMethod.post: return HTTP.Method.post;
        case HttpMethod.put: return HTTP.Method.put;
        case HttpMethod.delete_: return HTTP.Method.del;
        case HttpMethod.options: return HTTP.Method.options;
        case HttpMethod.trace: return HTTP.Method.trace;
        case HttpMethod.connect: return HTTP.Method.connect;
        case HttpMethod.patch: return HTTP.Method.patch;
    }
}
