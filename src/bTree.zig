const std = @import("std");
const BTreeNode = @import("bTreeNode.zig").BTreeNode;
const Ti = 2;
pub const MAX_KEYS = 2 * Ti - 1;
const MIN_KEYS = Ti - 1;

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
        const BTreeNodeK = BTreeNode(u64);
        root: ?*BTreeNodeK,
        auto_increment_key: usize,
        file: std.fs.File,

        pub fn init() !Self {
            var file = try std.fs.cwd().createFile("test.txt", .{ .read = true });
            // defer file.close();

            const writer = file.writer();
            var header = Header{ .root_node_offset = 0, .record_count = 0 };
            try header.write(writer);

            const node = std.heap.page_allocator.create(BTreeNodeK) catch unreachable;
            node.* = BTreeNodeK.init(true);
            return Self{ .root = node, .auto_increment_key = 0, .file = file };
        }

        pub fn deinit(self: *Self) void {
            if (self.root) |root_node| {
                root_node.deinit();
                std.heap.page_allocator.destroy(root_node);
                self.root = null;
            }
        }
        fn writeHeader(self: *Self) !void {
            try self.file.seekTo(0);
            try self.header.write(self.file.writer());
        }

        fn readHeader(self: *Self) !void {
            try self.file.seekTo(0);
            self.header = try Header.read(self.file.reader());
        }

        fn writeRecord(self: *Self, record: V) !u64 {
            const writer = self.file.writer();
            const seeker = self.file.seekableStream();

            // Get current file offset
            const offset = try seeker.getPos();

            // Write name length and bytes
            try writer.writeInt(u64, record.name.len, .little);
            try writer.writeAll(record.name);

            // Write email length and bytes
            try writer.writeInt(u64, record.email.len, .little);
            try writer.writeAll(record.email);

            return offset;
        }

        fn writeNode(self: *Self, node: *BTreeNodeK) !u64 {
            const writer = self.file.writer();
            const seeker = self.file.seekableStream();

            var child_offsets: [MAX_KEYS + 1]u64 = [_]u64{0} ** (MAX_KEYS + 1);

            if (!node.is_leaf) {
                for (0..node.num_keys + 1) |i| {
                    if (node.children[i]) |child| {
                        const offset = try self.writeNode(child);
                        child_offsets[i] = offset;
                    }
                }
            }

            const node_offset = try seeker.getPos();

            try writer.writeByte(node.num_keys);
            try writer.writeByte(@intFromBool(node.is_leaf));

            for (0..MAX_KEYS) |i| {
                try writer.writeInt(usize, node.keys[i], .little);
            }

            for (0..MAX_KEYS) |i| {
                try writer.writeInt(u64, node.values[i], .little); // record offsets
            }

            for (0..MAX_KEYS + 1) |i| {
                try writer.writeInt(u64, child_offsets[i], .little); // child node offsets
            }

            return node_offset;
        }

        pub fn insertRecord(self: *Self, value: V) !void {
            const key = self.auto_increment_key;
            try self.insert(key, value);
            self.auto_increment_key += 1;
        }

        pub fn insert(self: *Self, key: usize, value: V) !void {
            // Step 1: Write record to file
            const record_offset = try self.writeRecord(value);
            std.debug.print("The value of record offset is {d}\n", .{record_offset});

            if (self.header.root_node_offset == 0) {
                // Tree is empty — create new root node
                var root = BTreeNodeK.init(true);
                try root.insert(key, record_offset);
                const root_offset = try self.writeNode(&root);

                self.header.root_node_offset = root_offset;
                self.header.record_count += 1;
                try self.writeHeader();
                return;
            }

            // Step 2: Load root node from disk
            var root = try self.readNode(self.header.root_node_offset);

            if (root.num_keys == MAX_KEYS) {
                // Step 3: Root is full — split it
                var new_root = BTreeNodeK.init(false);
                const old_root_offset = self.header.root_node_offset;

                new_root.children_offsets[0] = old_root_offset;
                try new_root.splitChild(0, &root, self);

                // Step 4: Insert into new root
                try new_root.insert(key, record_offset);

                // Step 5: Write both root and new root to file
                const new_root_offset = try self.writeNode(&new_root);
                try self.writeNode(&root); // update split child

                self.header.root_node_offset = new_root_offset;
            } else {
                // Step 6: Root has space, insert normally
                try root.insert(key, record_offset);
                try self.writeNode(&root);
            }

            self.header.record_count += 1;
            try self.writeHeader();
        }

        pub fn traverse(self: *Self) void {
            if (self.root) |root| {
                root.traverse();
                std.debug.print("\n", .{});
            }
        }

        pub fn searchTree(self: *Self, key: usize) ?V {
            if (self.root) |root| {
                return root.search(key);
            }
            return null;
        }

        pub fn remove(self: *Self, key: usize) void {
            if (self.root) |root| {
                root.remove(key);

                if (root.num_keys == 0) {
                    if (root.is_leaf) {
                        self.root = null;
                    } else {
                        self.root = root.children[0];
                    }
                }
            }
        }
    };
}
