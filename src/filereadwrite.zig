const std = @import("std");

const MAX_KEYS = 4;
const HEADER_SIZE = 16;

const Header = struct {
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

const Record = struct {
    name: []const u8,
    email: []const u8,
};

const Node = struct {
    id: u64,
    is_leaf: bool,
    num_keys: u8,
    key_offsets: [MAX_KEYS]u64,
    child_ids: [MAX_KEYS + 1]u64,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const file_path = "btree_data_with_header.txt";

    // 1) Create file and write placeholder header (zeroed for now)
    var file = try std.fs.cwd().createFile(file_path, .{ .read = true });
    defer file.close();

    // Write empty header placeholder (16 bytes)

    var writer = file.writer();
    var header = Header{ .root_node_offset = 0, .record_count = 0 };
    try header.write(writer);
    // 2) Write records, store their offsets
    const records = [_]Record{
        .{ .name = "alice", .email = "alice@example.com" },
        .{ .name = "bob", .email = "bob@example.com" },
        .{ .name = "carol", .email = "carol@example.com" },
        .{ .name = "dave", .email = "dave@example.com" },
    };

    var offsets: [MAX_KEYS]u64 = undefined;

    for (records, 0..) |record, i| {
        const offset = try file.getEndPos();
        offsets[i] = offset;
        try writer.print("{s}|{s}\n", .{ record.name, record.email }); 
    }

    // 3) Align to 8 bytes for node writing (optional but nice)
    const current = try file.getEndPos();
    const aligned = std.mem.alignForward(u64, current, 8);
    const pad_len = aligned - current;
    try writer.writeByteNTimes(0, pad_len);

    // 4) Write node at aligned offset
    const node_offset = aligned;
    const node = Node{
        .id = node_offset,
        .is_leaf = true,
        .num_keys = 4,
        .key_offsets = offsets,
        .child_ids = [_]u64{0} ** (MAX_KEYS + 1),
    };

    // Seek to node_offset and write node
    try file.seekTo(node_offset);
    var node_writer = file.writer();
    try node_writer.writeInt(u64, node.id, .little);
    try node_writer.writeByte(@intFromBool(node.is_leaf));
    try node_writer.writeByte(node.num_keys);
    for (node.key_offsets) |k| try node_writer.writeInt(u64, k, .little);
    for (node.child_ids) |c| try node_writer.writeInt(u64, c, .little);

    header = Header{ .root_node_offset = node_offset, .record_count = @intCast(records.len) };

    // 5) Go back and write the header with root_node_offset and record_count
    try file.seekTo(0);
    const header_writer = file.writer();
    try header.write(header_writer);
    // // === READ PHASE ===
    {
        try file.seekTo(0);
        const header_reader = file.reader();
        const read_header = try Header.read(header_reader);

        std.debug.print("\nHeader: root_offset={d}, record_count={d}\n", .{ read_header.root_node_offset, read_header.record_count });

        try file.seekTo(read_header.root_node_offset);
        const read_node = try readNode(file.reader());

        std.debug.print("Read Node @ offset {d}:\n", .{read_node.id});
        std.debug.print("  is_leaf: {}\n", .{read_node.is_leaf});
        std.debug.print("  num_keys: {}\n", .{read_node.num_keys});

        for (read_node.key_offsets[0..read_node.num_keys]) |offset| {
            const rec = try readRecordAtOffset(&file, offset, allocator);
            std.debug.print("  Record : {s} <{s}> (offset {d})\n", .{ rec.name, rec.email, offset });
        }

        const name_rec = try searchByName(&file, allocator, "bobp");
        if (name_rec) |rec| {
            std.debug.print("  Record by name: {s} <{s}>\n", .{ rec.name, rec.email });
        }else {
            std.debug.print("Record not found\n",.{});
        }
    }
}

fn readNode(reader: anytype) !Node {
    var node = Node{
        .id = try reader.readInt(u64, .little),
        .is_leaf = (try reader.readByte()) != 0,
        .num_keys = try reader.readByte(),
        .key_offsets = [_]u64{0} ** MAX_KEYS,
        .child_ids = [_]u64{0} ** (MAX_KEYS + 1),
    };

    for (0..MAX_KEYS) |i| {
        node.key_offsets[i] = try reader.readInt(u64, .little);
    }
    for (0..MAX_KEYS + 1) |i| {
        node.child_ids[i] = try reader.readInt(u64, .little);
    }

    return node;
}

fn readRecordAtOffset(file: *std.fs.File, offset: u64, allocator: std.mem.Allocator) !Record {
    try file.seekTo(offset);
    var buf: [128]u8 = undefined;
    const line = try file.reader().readUntilDelimiterOrEof(&buf, '\n') orelse
        return error.InvalidRecordFormat;

    var splitter = std.mem.splitScalar(u8, line, '|');
    const name = splitter.next() orelse return error.InvalidRecordFormat;
    const email = splitter.next() orelse return error.InvalidRecordFormat;

    return Record{
        .name = try allocator.dupe(u8, name),
        .email = try allocator.dupe(u8, email),
    };
}

fn searchByName(file: *std.fs.File, allocator: std.mem.Allocator, name: []const u8) !?Record {
    // 1. Read header to find root
    try file.seekTo(0);
    const header = try Header.read(file.reader());

    // 2. Seek to root node
    try file.seekTo(header.root_node_offset);
    const root = try readNode(file.reader());

    // 3. For each key offset, load the record and compare names
    for (root.key_offsets[0..root.num_keys]) |offset| {
        const rec = try readRecordAtOffset(file, offset, allocator);
        if (std.mem.eql(u8, rec.name, name)) return rec;
    }

    return null; // Not found
}
