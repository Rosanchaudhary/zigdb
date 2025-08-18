const std = @import("std");
pub const Header = struct {
    root_node_offset: u64,
    record_count: u64,
    record_index: u64,

    pub fn write(self: Header, writer: std.fs.File.Writer) !void {
        try writer.writeInt(u64, self.root_node_offset, .little);
        try writer.writeInt(u64, self.record_count, .little);
        try writer.writeInt(u64, self.record_index, .little);
    }

    pub fn read(_: Header, reader: std.fs.File.Reader) !Header {
        return Header{
            .root_node_offset = try reader.readInt(u64, .little),
            .record_count = try reader.readInt(u64, .little),
            .record_index = try reader.readInt(u64, .little),
        };
    }
};
