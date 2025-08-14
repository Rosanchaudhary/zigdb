pub const Header = struct {
    root_node_offset: u64,
    record_count: u64,

    pub fn write(self: Header, writer: anytype) !void {
        try writer.writeInt(u64, self.root_node_offset, .little);
        try writer.writeInt(u64, self.record_count, .little);
    }

    pub fn read(reader: anytype) !Header {
        return Header{
            .root_node_offset = try reader.readInt(u64, .little),
            .record_count = try reader.readInt(u64, .little),
        };
    }
};