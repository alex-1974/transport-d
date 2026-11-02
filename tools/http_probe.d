import std.stdio : writeln;
import transport.http : HttpSink, HttpSource;
import transport.source : ByteRange;

int main(string[] args)
{
    if (args.length != 2) return 2;
    auto source = new HttpSource(args[1]);
    ubyte[4] range;
    auto read = source.read(ByteRange(4, 4), range[]);
    if (!read.ok || range != [4, 5, 6, 7]) return 3;
    if (source.responseInfo.statusCode != 206) return 6;

    auto sink = new HttpSink(args[1]);
    if (!sink.write(cast(const(ubyte)[])[9, 8, 7, 6]).ok) return 4;
    sink.close();
    if (!sink.result.ok) return 5;
    writeln("http integration probe passed");
    return 0;
}
