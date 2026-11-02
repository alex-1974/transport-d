import transport;
import std.stdio : writeln;

@safe unittest
{
    const ubyte[8] bytes = [0, 1, 2, 3, 4, 5, 6, 7];
    auto source = MemorySource(bytes[]);
    ubyte[3] output;
    auto result = source.read(ByteRange(2, 3), output[]);
    assert(result.ok && result.bytesRead == 3);
    assert(output == [2, 3, 4]);
    assert(source.read(ByteRange(7, 2), output[]).error == ReadError.invalidRange);
    assert(source.read(ByteRange(0, 4), output[], ReadLimits(3)).error == ReadError.limitExceeded);
    writeln("transport memory/range contract passed");
}
