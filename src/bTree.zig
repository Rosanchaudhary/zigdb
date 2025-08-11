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
        allocator:std.mem.Allocator,

        pub fn init(allocator:std.mem.Allocator) !Self {
            // Create files
            var header_file = try std.fs.cwd().createFile("btreeheader.db", .{ .read = true, .truncate = true });
            const record_file = try std.fs.cwd().createFile("btreerecord.db", .{ .read = true, .truncate = true });
            const node_file = try std.fs.cwd().createFile("btreenode.txt", .{ .read = true, .truncate = true });

            // Initialize the root node
            var root = BTreeNodeK.init(true);

            // Write the root node to the NODE FILE, not the header file!
            const offset = try Self.writeNodeStatic(&node_file, &root);

            // Write header to the HEADER FILE
            try header_file.seekTo(0);
            const header = Header{
                .root_node_offset = offset,
                .record_count = 0,
            };
            try header.write(header_file.writer());

            return Self{
                .header_file = header_file,
                .record_file = record_file,
                .node_file = node_file,
                .header = header,
                .allocator = allocator
            };
        }

        pub fn deinit(self: *Self) void {
            self.header_file.close();
            self.record_file.close();
            self.node_file.close();
            
        }

        // pub fn insertRecord(self: *Self, value: V) !void {
        //     const key = @as(usize, self.header.record_count);
        //     try self.insert(key, value);
        //     self.header.record_count += 1;
        //     try self.writeHeader();
        // }

        pub fn insert(self: *Self, value: V) !void {
            const record_offset = try self.writeRecord(value);
            var root = try self.readNode(self.header.root_node_offset);

            if (root.num_keys == MAX_KEYS) {
                var new_root = BTreeNodeK.init(false);
                new_root.children_offsets[0] = self.header.root_node_offset;
                try new_root.splitChild(0, &root, self);

                const new_root_offset = try self.writeNode(&new_root, true);

                self.header.root_node_offset = new_root_offset;
                try self.writeHeader();

                try new_root.insertNonFull(value.id, record_offset, self);
            } else {
                try root.insertNonFull(value.id, record_offset, self);
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

            const typeInfo = @typeInfo(V);
            const structInfo = typeInfo.@"struct";

            inline for (structInfo.fields) |field| {
                // Access the field value from `value`
                const field_value = @field(value, field.name);
                const field_type = field.type;

                switch (@typeInfo(field_type)) {
                    .pointer => |ptrInfo| {
                        if (ptrInfo.child == u8 and ptrInfo.size == .slice) {
                            try writer.writeInt(u64, field_value.len, .little);
                            try writer.writeAll(field_value);
                        } else {
                            @compileError("Only []u8 slices are supported for pointer types.");
                        }
                    },
                    .int => {
                        try writer.writeInt(field_type, field_value, .little);
                    },
                    .bool => {
                        try writer.writeByte(if (field_value) 1 else 0);
                    },
                    else => {
                        @compileError("Unsupported field type in writeRecord.");
                    },
                }

                // Make sure it's []u8 for now — or add type handling
                // try writer.writeInt(u64, field_value.len, .little);
                // try writer.writeAll(field_value);
            }

            return offset;
        }

        pub fn writeNode(self: *Self, node: *BTreeNodeK, is_root: bool) !u64 {
            const seeker = self.node_file.seekableStream();
            const writer = self.node_file.writer();

            // ✅ Use existing offset if it exists, otherwise append
            const offset = if (node.offset != 0) node.offset else try seeker.getEndPos();
            node.offset = offset; // ensure it's always tracked

            try seeker.seekTo(offset);

            try writer.writeByte(@intFromBool(node.is_leaf));
            try writer.writeByte(node.num_keys);

            for (0..MAX_KEYS) |i| {
                try writer.writeInt(usize, node.keys[i], .little);
            }

            for (0..MAX_KEYS) |i| {
                try writer.writeInt(u64, node.values[i], .little);
            }

            for (0..MAX_CHILDREN) |i| {
                try writer.writeInt(u64, node.children_offsets[i], .little);
            }

            if (is_root) {
                self.header.root_node_offset = offset;
                try self.writeHeader();
            }

            return offset;
        }

        pub fn writeNodeStatic(file: *const std.fs.File, node: *BTreeNodeK) !u64 {
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

            if (stat.size < node_serialized_size + offset)
                return error.InvalidOffset;

            var buffer: [node_serialized_size]u8 = undefined;
            try self.node_file.reader().readNoEof(&buffer);
            var stream = std.io.fixedBufferStream(&buffer);
            const reader = stream.reader();

            var node = BTreeNodeK.init(false);
            node.offset = offset; // <= ADD THIS
            node.is_leaf = try reader.readByte() != 0;
            node.num_keys = try reader.readByte();

            for (0..MAX_KEYS) |i| node.keys[i] = try reader.readInt(usize, .little);
            for (0..MAX_KEYS) |i| node.values[i] = try reader.readInt(u64, .little);
            for (0..MAX_CHILDREN) |i| node.children_offsets[i] = try reader.readInt(u64, .little);

            return node;
        }

        pub fn traverse(self: *Self) ![]V {
            const root = try self.readNode(self.header.root_node_offset);
            return try root.traverse(self, self.allocator);
        }

        pub fn readRecord(self: *Self, offset: u64) !V {
            
            const seeker = self.record_file.seekableStream();
            const reader = self.record_file.reader();

            try seeker.seekTo(offset);

            const typeInfo = @typeInfo(V);
            const structInfo = typeInfo.@"struct";

            var result: V = undefined;

            inline for (structInfo.fields) |field| {
                const field_type = field.type;

                switch (@typeInfo(field_type)) {
                    .pointer => |ptrInfo| {
                        // Handle []u8 only
                        if (ptrInfo.size == .slice and ptrInfo.child == u8) {
                            const field_len = try reader.readInt(u64, .little);
                            const field_buf = try self.allocator.alloc(u8, field_len);
                            try reader.readNoEof(field_buf);
                            @field(result, field.name) = field_buf;
                        } else {
                            @compileError("Only []u8 slice pointers are supported.");
                        }
                    },
                    .int => {
                        const value = try reader.readInt(field_type, .little);
                        @field(result, field.name) = value;
                    },
                    .bool => {
                        const b = try reader.readByte();
                        @field(result, field.name) = b != 0;
                    },
                    else => {
                        @compileError("Unsupported field type in readRecord.");
                    },
                }
            }

            return result;
        }

        pub fn traverseAllNodes(self: *Self) !void {
            const root = try self.readNode(self.header.root_node_offset);
            try root.traverseNodes(self);
        }

        pub fn search(self: *Self, key: usize) !?V {
            const root = try self.readNode(self.header.root_node_offset);
            const offset_opt = try root.search(key, self);
            if (offset_opt) |offset| {
                return try self.readRecord(offset);
            } else {
                return null;
            }
        }

        pub fn delete(self: *Self, key: usize) !bool {
            var root = try self.readNode(self.header.root_node_offset);

            // Attempt to delete the key from the root
            const deleted = try root.delete(key, self);

            // If root has 0 keys and is not a leaf, shrink the tree height
            if (root.num_keys == 0 and !root.is_leaf) {
                // Replace root with its only child
                var new_root = try self.readNode(root.children_offsets[0]);
                self.header.root_node_offset = try self.writeNode(&new_root, true);
            } else {
                // Write updated root (even if unchanged in structure, it may have fewer keys)
                self.header.root_node_offset = try self.writeNode(&root, true);
            }

            // Always write header in case root offset changed
            try self.writeHeader();
            std.debug.print("The value of deleted is {}\n", .{deleted});
            return deleted;
        }
    };
}
