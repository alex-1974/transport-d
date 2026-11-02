module transport.async;

import transport.source : ByteRange, ByteSource, ReadLimits, ReadResult;

interface AsyncOperation
{
    void cancel() @safe;
    @property bool cancelled() const @safe pure nothrow;
}

interface AsyncExecutor
{
    AsyncOperation submit(scope void delegate() @safe work) @safe;
}

alias AsyncReadCallback = void delegate(ReadResult result) @safe;

interface AsyncByteSource
{
    AsyncOperation readAsync(
        ByteRange range,
        scope ubyte[] destination,
        AsyncExecutor executor,
        scope AsyncReadCallback callback,
        ReadLimits limits = ReadLimits.init
    ) @safe;
}

private class InlineOperation : AsyncOperation
{
    private bool isCancelled;
    void cancel() @safe { isCancelled = true; }
    @property bool cancelled() const @safe pure nothrow { return isCancelled; }
}

/** Deterministic executor useful for tests and synchronous integration. */
class InlineExecutor : AsyncExecutor
{
    AsyncOperation submit(scope void delegate() @safe work) @safe
    {
        auto operation = new InlineOperation();
        if (!operation.cancelled)
            work();
        return operation;
    }
}

class AsyncSourceAdapter : AsyncByteSource
{
    private ByteSource source;

    this(ByteSource source) @safe
    {
        this.source = source;
    }

    AsyncOperation readAsync(
        ByteRange range,
        scope ubyte[] destination,
        AsyncExecutor executor,
        scope AsyncReadCallback callback,
        ReadLimits limits = ReadLimits.init
    ) @safe
    {
        return executor.submit(()
        {
            callback(source.read(range, destination, limits));
        });
    }
}
