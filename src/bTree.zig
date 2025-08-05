// bTree.zig
const std = @import("std");
const BTreeNode = @import("bTreeNode.zig").BTreeNode;
const Ti = 2;
const MAX_KEYS = 2 * Ti - 1;
const MAX_CHILDREN = MAX_KEYS + 1;

const node_serialized_size =
    1 + // is_leaf
    1 + // num_keys
    MAX_KEYS * @sizeOf(usize) +
    MAX_KEYS * @sizeOf(u64) +
    MAX_CHILDREN * @sizeOf(u64);

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

pub fn Btree(comptime V: type) type {
    return struct {
        const Self = @This();
        const BTreeNodeK = BTreeNode;

        header_file: std.fs.File,
        record_file: std.fs.File,
        node_file: std.fs.File,
        header: Header,

        pub fn init() !Self {
            var header_file = try std.fs.cwd().createFile("btreeheader.db", .{ .read = true, .truncate = true });
            const record_file = try std.fs.cwd().createFile("btreerecord.db", .{ .read = true, .truncate = true });
            const node_file = try std.fs.cwd().createFile("btreenode.txt", .{ .read = true, .truncate = true });

            var root = BTreeNodeK.init(true);
            const offset = try Self.writeNodeStatic(header_file, &root);

            try header_file.seekTo(0);
            const header = Header{ .root_node_offset = offset, .record_count = 0 };
            try header.write(header_file.writer());

            return Self{
                .header_file = header_file,
                .record_file = record_file,
                .node_file = node_file,
                .header = header,
            };
        }

        pub fn deinit(self: *Self) void {
            self.header_file.close();
            self.record_file.close();
            self.node_file.close();
        }

        pub fn insertRecord(self: *Self, value: V) !void {
            const key = @as(usize, self.header.record_count);
            try self.insert(key, value);
            self.header.record_count += 1;
            try self.writeHeader();
        }

        pub fn insert(self: *Self, key: usize, value: V) !void {
           
            const record_offset = try self.writeRecord(value);
            var root = try self.readNode(self.header.root_node_offset);

            if (root.num_keys == MAX_KEYS) {

                var new_root = BTreeNodeK.init(false);
                new_root.children_offsets[0] = self.header.root_node_offset;
                //new_root.print();
                try new_root.splitChild(0, &root, self);

                const new_root_offset = try self.writeNode(&new_root, true);
               
                self.header.root_node_offset = new_root_offset;
                try self.writeHeader();

                try new_root.insertNonFull(key, record_offset, self);
            } else {
                try root.insertNonFull(key, record_offset, self);
            }
        }

        fn writeHeader(self: *Self) !void {
            try self.header_file.seekTo(0);
            try self.header.write(self.header_file.writer());
        }

        fn writeRecord(self: *Self, value: V) !u64 {
            const seeker = self.record_file.seekableStream();
            try seeker.seekTo(try seeker.getEndPos());
            const writer = self.record_file.writer();
            const offset = try seeker.getPos();

            try writer.writeInt(u64, value.name.len, .little);
            try writer.writeAll(value.name);
            try writer.writeInt(u64, value.email.len, .little);
            try writer.writeAll(value.email);

            return offset;
        }

        pub fn writeNode(self: *Self, node: *BTreeNodeK, is_root: bool) !u64 {
            return try Self.writeNodeStaticTest(self, self.node_file, node, is_root);
        }

        pub fn writeNodeStaticTest(self: *Self, file: std.fs.File, node: *BTreeNodeK, is_root: bool) !u64 {
            //node.print();
            const seeker = file.seekableStream();
            const writer = file.writer();

            var offset: u64 = 0;
            if (is_root) {
                try seeker.seekTo(self.header.root_node_offset);
                offset = try seeker.getPos();
            } else {
                offset = try seeker.getEndPos(); // <- FIXED
                try seeker.seekTo(offset); // <- FIXED
            }

            try writer.writeByte(@intFromBool(node.is_leaf));
            try writer.writeByte(node.num_keys);

            for (0..MAX_KEYS) |i| try writer.writeInt(usize, node.keys[i], .little);
            for (0..MAX_KEYS) |i| try writer.writeInt(u64, node.values[i], .little);
            for (0..MAX_CHILDREN) |i| try writer.writeInt(u64, node.children_offsets[i], .little);

            return offset;
        }

        pub fn writeNodeStatic(file: std.fs.File, node: *BTreeNodeK) !u64 {
            const seeker = file.seekableStream();
            const writer = file.writer();
            const offset = try seeker.getPos();

            try writer.writeByte(@intFromBool(node.is_leaf));
            try writer.writeByte(node.num_keys);

            for (0..MAX_KEYS) |i| try writer.writeInt(usize, node.keys[i], .little);
            for (0..MAX_KEYS) |i| try writer.writeInt(u64, node.values[i], .little);
            for (0..MAX_CHILDREN) |i| try writer.writeInt(u64, node.children_offsets[i], .little);

            return offset;
        }

        pub fn readNode(self: *Self, offset: u64) !BTreeNodeK {
            try self.node_file.seekTo(offset);
            const stat = try self.node_file.stat();

            if (stat.size < node_serialized_size + offset) {
                const node = BTreeNodeK.init(true);
                return node;
            }

            var buffer: [node_serialized_size]u8 = undefined;
            try self.node_file.reader().readNoEof(&buffer);
            var stream = std.io.fixedBufferStream(&buffer);
            const reader = stream.reader();

            var node = BTreeNodeK.init(false);
            node.is_leaf = try reader.readByte() != 0;
            node.num_keys = try reader.readByte();

            for (0..MAX_KEYS) |i| node.keys[i] = try reader.readInt(usize, .little);
            for (0..MAX_KEYS) |i| node.values[i] = try reader.readInt(u64, .little);
            for (0..MAX_CHILDREN) |i| node.children_offsets[i] = try reader.readInt(u64, .little);

            return node;
        }

        pub fn traverse(self: *Self) !void {
            const root = try self.readNode(self.header.root_node_offset);
            try root.traverse(self);
        }

        pub fn readRecord(self: *Self, offset: u64) !V {
            const seeker = self.record_file.seekableStream();
            const reader = self.record_file.reader();

            try seeker.seekTo(offset);
            const name_len = try reader.readInt(u64, .little);
            const name_buf = try std.heap.page_allocator.alloc(u8, name_len);
            //defer std.heap.page_allocator.free(name_buf);
            try reader.readNoEof(name_buf);

            const email_len = try reader.readInt(u64, .little);
            const email_buf = try std.heap.page_allocator.alloc(u8, email_len);
            //defer std.heap.page_allocator.free(email_buf);
            try reader.readNoEof(email_buf);

            return V{
                .name = name_buf[0..name_len],
                .email = email_buf[0..email_len],
            };
        }

        pub fn traverseAllNodes(self: *Self) !void {
            const root = try self.readNode(self.header.root_node_offset);
            try root.traverseNodes(self);
        }
    };
}
