# Segmented byte buffer proposal for containers-d

Status: transport-d research evidence; not yet a containers-d API request.

## Observed consumer need

HTTP receive and upload callbacks operate on chunks. A consumer needs to:

- append borrowed `const(ubyte)[]` chunks;
- enforce a maximum total byte count before allocation grows;
- obtain the logical payload as independent borrowed segments;
- consume segments without flattening into one allocation;
- reset and reuse acquired capacity;
- keep earlier segments stable while later segments are acquired.

## Current transport prototype

`transport.buffer.SegmentedByteBuffer` implements this contract with fixed-size
segments and a maximum byte count. It is deliberately byte-specific and has no
thread-safety or allocator customization policy.

## Possible containers-d family

If a second independent consumer demonstrates the same semantics, the generic
candidate could be a `SegmentedBuffer!T` or a byte-specific
`SegmentedByteBuffer` family composed from the existing storage/lifetime
machinery.

The public contract must decide explicitly:

- whether growth is automatic or caller-established;
- whether segment sizes are uniform;
- whether borrowed segments remain stable after append;
- whether reset retains capacity;
- whether flattening is deliberately absent;
- how maximum capacity and allocation failure are reported;
- whether a bulk append operation is required.

The transport prototype is not a reason to add a general container early. Its
purpose is to provide real HTTP evidence for those decisions.
