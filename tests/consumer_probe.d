import transport;

/// Shared transport-shaped probe for non-image and imagery consumers.
@safe unittest
{
    const ubyte[8] osmBytes = [1, 2, 3, 4, 5, 6, 7, 8];
    const ubyte[8] satelliteBytes = [8, 7, 6, 5, 4, 3, 2, 1];
    auto osm = new ObservedSource(new MemorySource(osmBytes[]));
    auto satellite = new ObservedSource(new MemorySource(satelliteBytes[]));
    ubyte[3] osmWindow;
    ubyte[3] satelliteWindow;

    auto osmRead = osm.read(ByteRange(1, 3), osmWindow[]);
    auto satelliteRead = satellite.read(ByteRange(4, 3), satelliteWindow[]);
    assert(osmRead.ok && satelliteRead.ok);
    assert(osmWindow == [2, 3, 4]);
    assert(satelliteWindow == [4, 3, 2]);
    assert(osm.report.requests == 1 && osm.report.bytesRead == 3);
    assert(satellite.report.requests == 1 && satellite.report.bytesRead == 3);
}
