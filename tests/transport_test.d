import transport;
import std.file : read, remove, write;
import std.exception : collectException;
import std.stdio : writeln;

@safe unittest
{
    const ubyte[8] bytes = [0, 1, 2, 3, 4, 5, 6, 7];
    auto source = MemorySource(bytes[]);
    assert(source.provenance.scheme == "memory");
    assert(source.sourceInfo.lengthKnown && source.sourceInfo.length == bytes.length);
    assert(source.sourceInfo.rangeCapable);
    ubyte[3] output;
    auto result = source.read(ByteRange(2, 3), output[]);
    assert(result.ok && result.bytesRead == 3);
    assert(output == [2, 3, 4]);
    assert(source.read(ByteRange(7, 2), output[]).error == ReadError.invalidRange);
    assert(source.read(ByteRange(ulong.max, 2), output[]).error == ReadError.invalidRange);
    assert(source.read(ByteRange(0, 4), output[], ReadLimits(3)).error == ReadError.limitExceeded);
    ubyte[3] partial;
    auto partialRead = source.readSome(6, partial[]);
    assert(partialRead.ok && partialRead.bytesRead == 2);
    assert(partial[0 .. 2] == [6, 7]);
    assert(source.readSome(8, partial[]).error == ReadError.endOfSource);
    auto sink = new MemorySink();
    auto transfer = copyTo(source, sink, TransferLimits(8, 3));
    assert(transfer.ok && sink.data == bytes[]);
    auto reader = new SourceReader(source);
    auto streamSink = new MemorySink();
    auto writer = new SinkWriter(streamSink);
    auto streamTransfer = copyTo(reader, writer, TransferLimits(8, 3));
    assert(streamTransfer.ok && streamTransfer.bytesTransferred == bytes.length);
    assert(streamSink.data == bytes[]);
    auto cursor = new SourceReader(source, 5);
    ubyte[4] tail;
    auto tailRead = cursor.read(tail[]);
    assert(tailRead.ok && tailRead.bytesRead == 3 && cursor.position == 8);
    assert(tail[0 .. 3] == [5, 6, 7]);
    assert(cursor.read(tail[]).error == ReadError.endOfSource);
    writeln("transport memory/range contract passed");
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
    assert(result.ok && result.bytesRead == 3);
    assert(output == [12, 13, 14]);
    assert(source.read(ByteRange(7, 2), output[]).error == ReadError.invalidRange);
    assert(source.read(ByteRange(8, 1), output[]).error == ReadError.endOfSource);
    assert(source.read(ByteRange(0, 4), output[]).error == ReadError.destinationTooSmall);

    enum outputPath = "/tmp/transport-d-file-output.bin";
    scope (exit) remove(outputPath);
    auto sink = new FileSink(outputPath);
    auto transfer = copyTo(source, sink, TransferLimits(8, 3));
    assert(transfer.ok && transfer.bytesTransferred == bytes.length);
    assert(cast(const(ubyte)[]) read(outputPath) == bytes[]);

    auto overwrite = new FileSink(outputPath);
    assert(overwrite.write([99]).ok);
    overwrite.close();
    assert(!overwrite.isOpen);
    assert(!overwrite.write([100]).ok);
    assert(cast(const(ubyte)[]) read(outputPath) == [99]);
}

@safe unittest
{
    auto missing = new FileSource("/tmp/transport-d-file-does-not-exist.bin");
    ubyte[1] output;
    assert(missing.read(ByteRange(0, 1), output[]).error == ReadError.sourceFailure);

    auto sink = new MemorySink();
    assert(sink.write([1, 2, 3], WriteLimits(2)).error == WriteError.limitExceeded);
    assert(sink.data.length == 0);

    auto upload = new HttpSink("http://127.0.0.1:1/upload");
    assert(upload.write([1, 2, 3]).ok);
    upload.close();
    assert(upload.isClosed);
    assert(!upload.write([4]).ok);

    auto segmented = new SegmentedByteBuffer(3, 8);
    assert(segmented.append([1, 2, 3, 4, 5]).ok);
    assert(segmented.length == 5);
    assert(segmented.chunkCount == 2);
    assert(segmented.chunks[0] == [1, 2, 3]);
    assert(segmented.chunks[1] == [4, 5]);
    auto firstChunk = segmented.chunks[0];
    assert(segmented.write([6, 7, 8, 9]).error == WriteError.limitExceeded);
    assert(segmented.length == 5);
    assert(firstChunk == [1, 2, 3]);
    segmented.reset();
    assert(segmented.length == 0 && segmented.capacity == 6);
    assert(segmented.maximumBytes == 8);
    assert(segmented.write([9, 8]).ok);
    assert(collectException!Exception(new SegmentedByteBuffer(0)) !is null);

    auto asyncSource = new AsyncSourceAdapter(source);
    auto executor = new InlineExecutor();
    ubyte[2] asyncOutput;
    bool callbackCalled;
    auto operation = asyncSource.readAsync(ByteRange(1, 2), asyncOutput[], executor,
        (ReadResult result)
        {
            callbackCalled = true;
            assert(result.ok && result.bytesRead == 2);
        });
    assert(operation !is null && !operation.cancelled);
    assert(callbackCalled && asyncOutput == [1, 2]);
}
