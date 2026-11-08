import std.stdio : writeln;
import transport.http : HttpSink, HttpSource;
import transport.source : ByteRange, ReadError;

int main(string[] args)
{
    if (args.length != 2) return 2;
    auto source = new HttpSource(args[1]);
    ubyte[4] range;
    auto read = source.read(ByteRange(4, 4), range[]);
    if (!read.hasValue || range != [4, 5, 6, 7]) return 3;
    if (source.responseInfo.statusCode != 206) return 6;
    ubyte[4] tail;
    auto partial = source.readSome(30, tail[]);
    if (!partial.hasValue || partial.value.bytesRead != 2 || tail[0 .. 2] != [30, 31]) return 7;
    if (source.readSome(32, tail[]).error.kind != ReadError.endOfSource) return 8;
    if (!source.sourceInfo.lengthKnown || source.sourceInfo.length != 32) return 9;

    auto sink = new HttpSink(args[1]);
    if (!sink.write(cast(const(ubyte)[])[9, 8, 7, 6]).hasValue) return 4;
    sink.close();
    if (!sink.result.hasValue) return 5;
    writeln("http integration probe passed");
    return 0;
}
