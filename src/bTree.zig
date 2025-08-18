// bTree.zig
const std = @import("std");
const BTreeNode = @import("bTreeNode.zig").BtreeNode;
const RecordMetadata = @import("recordStruct.zig").RecordMetadata;
const Header = @import("header.zig").Header;
const constants = @import("constants.zig");

const MAX_KEYS = constants.MAX_KEYS;
const MAX_CHILDREN = constants.MAX_CHILDREN;
const node_serialized_size = constants.node_serialized_size;

pub fn Btree(comptime V: type) type {
    return struct {
        const Self = @This();
        const BTreeNodeK = BTreeNode(V);
        const RecordMetadataType = RecordMetadata(V);

        header_file: std.fs.File,
        record_file: std.fs.File,
        node_file: std.fs.File,
        header: Header,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !Self {
            // Create files
            var header_file = try std.fs.cwd().createFile("btreeheader.db", .{ .read = true, .truncate = true });
            const record_file = try std.fs.cwd().createFile("btreerecord.db", .{ .read = true, .truncate = true });
            const node_file = try std.fs.cwd().createFile("btreenode.db", .{ .read = true, .truncate = true });
  

            // Initialize the root node
            var root = BTreeNodeK.init(true);

            // Write the root node to the NODE FILE, not the header file!
            const offset = try Self.writeNodeStatic(&node_file, &root);

            // Write header to the HEADER FILE
            try header_file.seekTo(0);
            const header = Header{ .root_node_offset = offset, .record_count = 0, .record_index = 1 };
            try header.write(header_file.writer());

            return Self{ .header_file = header_file, .record_file = record_file, .node_file = node_file, .header = header, .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.header_file.close();
            self.record_file.close();
            self.node_file.close();
        }
        pub fn insert(self: *Self, value: V) !void {
            // Reading header for index and count
            try self.header_file.seekTo(0);
            self.header = try self.header.read(self.header_file.reader());

            const rec_id = self.header.record_index;

            // ---- Write metadata fields ----
            const meta = try RecordMetadata(V).init(rec_id, value, self.allocator);
            const record_offset = try self.writeRecord(meta);

            var root = try self.readNode(self.header.root_node_offset);

            if (root.num_keys == MAX_KEYS) {
                var new_root = BTreeNodeK.init(false);
                new_root.children_offsets[0] = self.header.root_node_offset;
                try new_root.splitChild(0, &root, self);

                const new_root_offset = try self.writeNode(&new_root, true);
                self.header.root_node_offset = new_root_offset;

                try new_root.insertNonFull(rec_id, record_offset, self);
            } else {
                try root.insertNonFull(rec_id, record_offset, self);
            }

            // Update header and persist
            self.header.record_index += 1;
            self.header.record_count += 1;
            try self.writeHeader();
        }

        fn writeRecord(self: *Self, meta: RecordMetadataType) !u64 {
            const seeker = self.record_file.seekableStream();
            try seeker.seekTo(try seeker.getEndPos());
            const writer = self.record_file.writer();
            const offset = try seeker.getPos();

            // id
            try writer.writeInt(@TypeOf(meta.id), meta.id, .little);

            //version
            try writer.writeInt(@TypeOf(meta.version), meta.version, .little);
            // previous_versions_offsets (slice)
            try writer.writeInt(u64, meta.previous_versions_offsets.len, .little);
            for (meta.previous_versions_offsets) |off| {
                try writer.writeInt(u64, off, .little);
            }

            // created_at
            try writer.writeInt(@TypeOf(meta.created_at), meta.created_at, .little);

            // updated_at
            try writer.writeInt(@TypeOf(meta.updated_at), meta.updated_at, .little);

            // deleted flag
            try writer.writeByte(if (meta.deleted) 1 else 0);

            // ---- Write actual Record data ----
            const recordTypeInfo = @typeInfo(@TypeOf(meta.data));
            const recordStructInfo = recordTypeInfo.@"struct";

            inline for (recordStructInfo.fields) |field| {
                const field_value = @field(meta.data, field.name);
                const field_type = field.type;

                switch (@typeInfo(field_type)) {
                    .pointer => |ptrInfo| {
                        if (ptrInfo.child == u8 and ptrInfo.size == .slice) {
                            try writer.writeInt(u64, field_value.len, .little);
                            try writer.writeAll(field_value);
                        } else {
                            @compileError("Only []u8 slices are supported for pointer types in Record.");
                        }
                    },
                    .int => {
                        try writer.writeInt(field_type, field_value, .little);
                    },
                    .bool => {
                        try writer.writeByte(if (field_value) 1 else 0);
                    },
                    else => {
                        @compileError("Unsupported field type in Record.");
                    },
                }
            }

            return offset;
        }

        pub fn readRecord(self: *Self, offset: u64) !RecordMetadataType {
            const seeker = self.record_file.seekableStream();
            try seeker.seekTo(offset);
            const reader = self.record_file.reader();

            var meta: RecordMetadataType = undefined;

            // ---- Read metadata ----
            meta.id = try reader.readInt(@TypeOf(meta.id), .little);
            meta.version = try reader.readInt(@TypeOf(meta.version), .little);

            // previous_versions_offsets slice
            const prev_len = try reader.readInt(u64, .little);
            meta.previous_versions_offsets = try self.allocator.alloc(u64, prev_len);
            for (meta.previous_versions_offsets) |*off| {
                off.* = try reader.readInt(u64, .little);
            }

            meta.created_at = try reader.readInt(@TypeOf(meta.created_at), .little);
            meta.updated_at = try reader.readInt(@TypeOf(meta.updated_at), .little);

            const deleted_flag = try reader.readByte();
            meta.deleted = (deleted_flag != 0);

            // ---- Read Record data ----
            var record: V = undefined;
            const recordTypeInfo = @typeInfo(V);
            const recordStructInfo = recordTypeInfo.@"struct";

            inline for (recordStructInfo.fields) |field| {
                const field_type = field.type;
                switch (@typeInfo(field_type)) {
                    .pointer => |ptrInfo| {
                        if (ptrInfo.child == u8 and ptrInfo.size == .slice) {
                            const len = try reader.readInt(u64, .little);
                            const buf = try self.allocator.alloc(u8, len);
                            try reader.readNoEof(buf);
                            @field(record, field.name) = buf;
                        } else {
                            @compileError("Only []u8 slices are supported for pointer types in Record.");
                        }
                    },
                    .int => {
                        @field(record, field.name) = try reader.readInt(field_type, .little);
                    },
                    .bool => {
                        @field(record, field.name) = (try reader.readByte() != 0);
                    },
                    else => {
                        @compileError("Unsupported field type in Record.");
                    },
                }
            }

            meta.data = record;

            return meta; // Only return the Record for now
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

        pub fn traverse(self: *Self) ![]RecordMetadataType {
            const root = try self.readNode(self.header.root_node_offset);
            return try root.traverse(self, self.allocator);
        }

        fn writeHeader(self: *Self) !void {
            try self.header_file.seekTo(0);
            try self.header.write(self.header_file.writer());
        }

        pub fn traverseAllNodes(self: *Self) !void {
            const root = try self.readNode(self.header.root_node_offset);
            try root.traverseNodes(self);
        }

        pub fn search(self: *Self, key: usize) !?RecordMetadataType {
            const root = try self.readNode(self.header.root_node_offset);
            const offset_opt = try root.search(key, self);
            if (offset_opt) |offset| {
                return try self.readRecord(offset);
            } else {
                return null;
            }
        }

        pub fn updateById(self: *Self, key: usize, newRecord: V) !bool {
            const root = try self.readNode(self.header.root_node_offset);
            const search_result = try root.searchNodeOffsetAndIndex(key, self);

            if (search_result) |result| {
                var node = try self.readNode(result.node_offset);
                const oldRecord = try self.readRecord(node.values[result.index]);
                var offset_list = std.ArrayList(u64).init(self.allocator);
                defer offset_list.deinit();

                //push all previous offsets
                try offset_list.appendSlice(oldRecord.previous_versions_offsets);

                // Push new offset
                try offset_list.append(node.values[result.index]);
                const newMeta: RecordMetadataType = try RecordMetadata(V).update(oldRecord.id, newRecord, offset_list.items, oldRecord.created_at);
                const new_offset = try self.writeRecord(newMeta);
                node.values[result.index] = new_offset;

                _ = try self.writeNode(&node, false);
                return true;
            } else {
                return false;
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
