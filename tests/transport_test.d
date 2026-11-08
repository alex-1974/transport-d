import transport;
import std.file : read, remove, write;
import std.exception : collectException;
import std.stdio : writeln;
import error_d : Result;

private final class FakeExchange : HttpExchange
{
    HttpResponse response;
    bool fail;
    HttpExchangeResult exchange(scope const ref HttpRequest request) @safe
    {
        if (fail)
            return HttpExchangeResult.failure(HttpExchangeError(
                HttpExchangeErrorKind.transportFailure));
        return HttpExchangeResult.success(response);
    }
}

@safe unittest
{
    const ubyte[8] bytes = [0, 1, 2, 3, 4, 5, 6, 7];
    auto source = new MemorySource(bytes[]);
    assert(source.provenance.scheme == "memory");
    assert(source.sourceInfo.lengthKnown && source.sourceInfo.length == bytes.length);
    assert(source.sourceInfo.rangeCapable);
    ubyte[3] output;
    auto result = source.read(ByteRange(2, 3), output[]);
    assert(result.hasValue && result.value.bytesRead == 3);
    assert(output == [2, 3, 4]);
    assert(source.read(ByteRange(7, 2), output[]).error.kind == ReadError.invalidRange);
    assert(source.read(ByteRange(ulong.max, 2), output[]).error.kind == ReadError.invalidRange);
    assert(source.read(ByteRange(0, 4), output[], ReadLimits(3)).error.kind == ReadError.limitExceeded);
    ubyte[3] partial;
    auto partialRead = source.readSome(6, partial[]);
    assert(partialRead.hasValue && partialRead.value.bytesRead == 2);
    assert(partial[0 .. 2] == [6, 7]);
    assert(source.readSome(8, partial[]).error.kind == ReadError.endOfSource);
    auto sink = new MemorySink();
    auto transfer = copyTo(source, sink, TransferLimits(8, 3));
    assert(transfer.hasValue && sink.data == bytes[]);
    auto reader = new SourceReader(source);
    auto streamSink = new MemorySink();
    auto writer = new SinkWriter(streamSink);
    auto streamTransfer = copyTo(reader, writer, TransferLimits(8, 3));
    assert(streamTransfer.hasValue && streamTransfer.value.bytesTransferred == bytes.length);
    assert(streamSink.data == bytes[]);
    auto cursor = new SourceReader(source, 5);
    ubyte[4] tail;
    auto tailRead = cursor.read(tail[]);
    assert(tailRead.hasValue && tailRead.value.bytesRead == 3 && cursor.position == 8);
    assert(tail[0 .. 3] == [5, 6, 7]);
    assert(cursor.read(tail[]).error.kind == ReadError.endOfSource);
    enum readerPath = "/tmp/transport-d-reader-test.bin";
    write(readerPath, bytes[]);
    scope (exit) remove(readerPath);
    auto fileReader = new FileReader(readerPath);
    ubyte[3] readerChunk;
    assert(fileReader.read(readerChunk[]).value.bytesRead == 3);
    assert(fileReader.position == 3);
    fileReader.close();
    assert(fileReader.isClosed);
    assert(fileReader.read(readerChunk[]).error.kind == ReadError.sourceFailure);
    writeln("transport memory/range contract passed");
}

@safe unittest
{
    auto body = new SegmentedByteBuffer(4, 16);
    assert(body.write([4, 5, 6]).hasValue);
    auto fake = new FakeExchange();
    fake.response = HttpResponse(409, "Conflict", ["content-type": "text/plain"],
        "https://example.test/edit", body);

    HttpRequest request;
    request.method = HttpMethod.put;
    request.url = "https://example.test/edit";
    request.sensitiveHeaders = ["Authorization": "Bearer secret"];
    request.body = body;
    auto response = fake.exchange(request);
    assert(response.hasValue);
    assert(response.value.statusCode == 409);
    assert(response.value.body.length == 3);

    fake.fail = true;
    auto failure = fake.exchange(request);
    assert(failure.hasError);
    assert(failure.error.kind == HttpExchangeErrorKind.transportFailure);

    request.options.maxRedirects = 1;
    auto native = new CurlHttpExchange();
    auto rejected = native.exchange(request);
    assert(rejected.hasError);
    assert(rejected.error.kind == HttpExchangeErrorKind.invalidRequest);
}

@safe unittest
{
    enum path = "/tmp/transport-d-file-test.bin";
    const ubyte[8] bytes = [10, 11, 12, 13, 14, 15, 16, 17];
    write(path, bytes[]);
    scope (exit) remove(path);

    auto source = new FileSource(path);
    assert(source.provenance.identifier == path);
    assert(source.sourceInfo.lengthKnown && source.sourceInfo.length == bytes.length);
    ubyte[3] output;
    auto result = source.read(ByteRange(2, 3), output[]);
    assert(result.hasValue && result.value.bytesRead == 3);
    assert(output == [12, 13, 14]);
    assert(source.read(ByteRange(7, 2), output[]).error.kind == ReadError.invalidRange);
    assert(source.read(ByteRange(8, 1), output[]).error.kind == ReadError.endOfSource);
    assert(source.read(ByteRange(0, 4), output[]).error.kind == ReadError.destinationTooSmall);

    enum outputPath = "/tmp/transport-d-file-output.bin";
    scope (exit) remove(outputPath);
    auto sink = new FileSink(outputPath);
    auto transfer = copyTo(source, sink, TransferLimits(8, 3));
    assert(transfer.hasValue && transfer.value.bytesTransferred == bytes.length);
    assert(cast(const(ubyte)[]) read(outputPath) == bytes[]);

    auto overwrite = new FileSink(outputPath);
    assert(overwrite.write([99]).hasValue);
    overwrite.close();
    assert(!overwrite.isOpen);
    assert(overwrite.write([100]).hasError);
    assert(cast(const(ubyte)[]) read(outputPath) == [99]);
}

@safe unittest
{
    auto missing = new FileSource("/tmp/transport-d-file-does-not-exist.bin");
    ubyte[1] output;
    assert(missing.read(ByteRange(0, 1), output[]).error.kind == ReadError.sourceFailure);

    auto sink = new MemorySink();
    assert(sink.write([1, 2, 3], WriteLimits(2)).error.kind == WriteError.limitExceeded);
    assert(sink.data.length == 0);

    auto upload = new HttpSink("http://127.0.0.1:1/upload");
    assert(upload.write([1, 2, 3]).hasValue);
    upload.close();
    assert(upload.isClosed);
    assert(upload.write([4]).hasError);

    auto segmented = new SegmentedByteBuffer(3, 8);
    assert(segmented.append([1, 2, 3, 4, 5]).hasValue);
    assert(segmented.length == 5);
    assert(segmented.chunkCount == 2);
    assert(segmented.chunks[0] == [1, 2, 3]);
    assert(segmented.chunks[1] == [4, 5]);
    auto firstChunk = segmented.chunks[0];
    assert(segmented.write([6, 7, 8, 9]).error.kind == WriteError.limitExceeded);
    assert(segmented.length == 5);
    assert(firstChunk == [1, 2, 3]);
    segmented.reset();
    assert(segmented.length == 0 && segmented.capacity == 6);
    assert(segmented.maximumBytes == 8);
    assert(segmented.write([9, 8]).hasValue);
    assert(collectException!Exception(new SegmentedByteBuffer(0)) !is null);

    auto asyncSource = new AsyncSourceAdapter(new MemorySource([0, 1, 2, 3]));
    auto executor = new InlineExecutor();
    ubyte[2] asyncOutput;
    bool callbackCalled;
    auto operation = asyncSource.readAsync(ByteRange(1, 2), asyncOutput[], executor,
        (ReadResult result)
        {
            callbackCalled = true;
            assert(result.hasValue && result.value.bytesRead == 2);
        });
    assert(operation !is null && !operation.cancelled);
    assert(callbackCalled && asyncOutput == [1, 2]);
}
