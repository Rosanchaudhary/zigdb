// bTreeNode.zig
const std = @import("std");
const BTree = @import("bTree.zig").Btree;

const RecordMetadata = @import("recordStruct.zig").RecordMetadata;
const Ti = 2;
const MAX_KEYS = 2 * Ti - 1;
const MIN_KEYS = Ti - 1;
const MAX_CHILDREN = MAX_KEYS + 1;

pub fn BtreeNode(comptime V: type) type {
    return struct {
        const Self = @This();
        const BTreeType = BTree(V);
        const RecordMetadataType = RecordMetadata(V);

        offset: u64 = 0, // <= NEW FIELD!
        keys: [MAX_KEYS]usize,
        values: [MAX_KEYS]u64,
        children_offsets: [MAX_CHILDREN]u64,
        num_keys: u8,
        is_leaf: bool,

        pub fn init(is_leaf: bool) Self {
            return Self{
                .offset = 0, // <= INIT offset
                .keys = [_]usize{0} ** MAX_KEYS,
                .values = [_]u64{0} ** MAX_KEYS,
                .children_offsets = [_]u64{0} ** MAX_CHILDREN,
                .num_keys = 0,
                .is_leaf = is_leaf,
            };
        }

        pub fn print(self: *const Self) void {
            std.debug.print("Self:\n", .{});
            std.debug.print("  is_leaf: {}\n", .{self.is_leaf});
            std.debug.print("  num_keys: {}\n", .{self.num_keys});
            std.debug.print("  keys: ", .{});
            for (self.keys[0..self.num_keys]) |key| {
                std.debug.print("{} ", .{key});
            }
            std.debug.print("\n", .{});

            std.debug.print("  values: ", .{});
            for (self.values[0..self.num_keys]) |value| {
                std.debug.print("{} ", .{value});
            }
            std.debug.print("\n", .{});

            if (!self.is_leaf) {
                std.debug.print("  children_offsets: ", .{});
                for (self.children_offsets[0 .. self.num_keys + 1]) |offset| {
                    std.debug.print("{} ", .{offset});
                }
                std.debug.print("\n", .{});
            }
        }

        pub fn traverseNodes(self: *const Self, tree: BTreeType) !void {
            std.debug.print("======= NODE =======\n", .{});
            self.print();

            if (!self.is_leaf) {
                for (self.children_offsets[0 .. self.num_keys + 1]) |offset| {
                    const child = try tree.readNode(offset);
                    try child.traverseNodes(tree);
                }
            }
        }

        fn findKeyIndex(self: *const Self, key: usize) usize {
            var left: usize = 0;
            var right: usize = self.num_keys;

            while (left < right) {
                const mid = (left + right) / 2;
                if (self.keys[mid] < key) {
                    left = mid + 1;
                } else {
                    right = mid;
                }
            }

            return left;
        }

        pub fn insertNonFull(self: *Self, key: usize, record_offset: u64, tree: *BTreeType) !void {
            if (self.is_leaf) {
                const i = self.findKeyIndex(key);

                var j = self.num_keys;
                while (j > i) : (j -= 1) {
                    self.keys[j] = self.keys[j - 1];
                    self.values[j] = self.values[j - 1];
                }

                self.keys[i] = key;
                self.values[i] = record_offset;
                self.num_keys += 1;

                _ = try tree.writeNode(self, true);
            } else {
                var i = self.findKeyIndex(key);
                var child = try tree.readNode(self.children_offsets[i]);

                if (child.num_keys == MAX_KEYS) {
                    try self.splitChild(i, &child, tree);

                    if (key > self.keys[i]) {
                        i += 1;
                    }

                    child = try tree.readNode(self.children_offsets[i]);
                }

                try child.insertNonFull(key, record_offset, tree);
                const new_offset = try tree.writeNode(&child, false);
                self.children_offsets[i] = new_offset;

                _ = try tree.writeNode(self, true);
            }
        }

        pub fn splitChild(self: *Self, i: usize, y: *Self, tree: *BTreeType) !void {
            var z = Self.init(y.is_leaf);
            z.num_keys = MIN_KEYS;

            for (MIN_KEYS + 1..MAX_KEYS) |j| {
                z.keys[j - (MIN_KEYS + 1)] = y.keys[j];
                z.values[j - (MIN_KEYS + 1)] = y.values[j];
            }

            if (!y.is_leaf) {
                for (MIN_KEYS + 1..MAX_CHILDREN) |j| {
                    z.children_offsets[j - (MIN_KEYS + 1)] = y.children_offsets[j];
                }
            }

            y.num_keys = MIN_KEYS;

            var j = self.num_keys;
            while (j > i) : (j -= 1) self.children_offsets[j + 1] = self.children_offsets[j];

            const z_offset = try tree.writeNode(&z, false);
            self.children_offsets[i + 1] = z_offset;

            j = self.num_keys;
            while (j > i) : (j -= 1) {
                self.keys[j] = self.keys[j - 1];
                self.values[j] = self.values[j - 1];
            }

            self.keys[i] = y.keys[MIN_KEYS];
            self.values[i] = y.values[MIN_KEYS];
            self.num_keys += 1;

            const y_offset = try tree.writeNode(y, false);
            self.children_offsets[i] = y_offset;

            _ = try tree.writeNode(self, true);
        }

        pub fn traverse(self: *const Self, tree: *BTreeType, allocator: std.mem.Allocator) ![]RecordMetadataType {
            var records = std.ArrayList(RecordMetadataType).init(allocator);

            var i: usize = 0;
            while (i < self.num_keys) {
                if (!self.is_leaf) {
                    const child = try tree.readNode(self.children_offsets[i]);
                    const child_records = try child.traverse(tree, allocator);
                    try records.appendSlice(child_records);
                }

                const record = try tree.readRecord(self.values[i]);
                try records.append(record);

                i += 1;
            }

            if (!self.is_leaf) {
                const child = try tree.readNode(self.children_offsets[i]);
                const child_records = try child.traverse(tree, allocator);
                try records.appendSlice(child_records);
            }

            return try records.toOwnedSlice();
        }

        pub fn search(self: *const Self, key: usize, tree: *BTreeType) !?u64 {
            const i = self.findKeyIndex(key);

            if (i < self.num_keys and self.keys[i] == key) {
                return self.values[i]; // Found
            }

            if (self.is_leaf) {
                return null; // Not found in leaf
            }

            const child = try tree.readNode(self.children_offsets[i]);
            return try child.search(key, tree);
        }

        pub fn searchNodeOffsetAndIndex(self: *const Self, key: usize, tree: *BTreeType) !?struct {
            node_offset: u64,
            index: usize,
        } {
            const i = self.findKeyIndex(key);

            if (i < self.num_keys and self.keys[i] == key) {
                return .{ .node_offset = self.offset, .index = i };
            }

            if (self.is_leaf) {
                return null;
            }

            const child = try tree.readNode(self.children_offsets[i]);
            return try child.searchNodeOffsetAndIndex(key, tree);
        }

        pub fn delete(self: *Self, key: usize, tree: *BTreeType) !bool {
            const i = self.findKeyIndex(key);

            // Case 1: key is present in this node
            if (i < self.num_keys and key == self.keys[i]) {
                // If this node is a leaf, delete directly from the leaf.
                if (self.is_leaf) {
                    return self.deleteInLeafPath(key, tree);
                }

                // Otherwise node is internal. Try predecessor first.
                var left_child: Self = try tree.readNode(self.children_offsets[i]);
                if (left_child.num_keys >= MIN_KEYS + 1) {
                    const pred = try self.getPredecessor(i, tree);
                    self.keys[i] = pred.key;
                    self.values[i] = pred.value;
                    // write parent but do not claim it's the root here
                    _ = try tree.writeNode(self, false);

                    const deleted = try left_child.deleteInLeafPath(pred.key, tree);
                    const left_offset = try tree.writeNode(&left_child, false);
                    self.children_offsets[i] = left_offset;
                    return deleted;
                }

                var right_child: Self = try tree.readNode(self.children_offsets[i + 1]);
                if (right_child.num_keys >= MIN_KEYS + 1) {
                    const succ = try self.getSuccessor(i, tree);
                    self.keys[i] = succ.key;
                    self.values[i] = succ.value;
                    _ = try tree.writeNode(self, false);

                    const deleted = try right_child.deleteInLeafPath(succ.key, tree);
                    const right_offset = try tree.writeNode(&right_child, false);
                    self.children_offsets[i + 1] = right_offset;
                    return deleted;
                }

                // Neither child has extra keys: merge and recurse into merged child
                try self.mergeChildren(i, &left_child, &right_child, tree);
                const deleted = try left_child.delete(key, tree);
                const new_offset = try tree.writeNode(&left_child, false);
                self.children_offsets[i] = new_offset;
                return deleted;
            }

            // Case 2: key not in this node
            if (self.is_leaf) {
                // key not found in leaf
                return false;
            }

            var child: Self = try tree.readNode(self.children_offsets[i]);

            // Ensure child has at least MIN_KEYS + 1 before recursing into it
            if (child.num_keys == MIN_KEYS) {
                if (i > 0) {
                    var left_sibling = try tree.readNode(self.children_offsets[i - 1]);
                    if (left_sibling.num_keys > MIN_KEYS) {
                        try child.borrowFromLeft(i - 1, &left_sibling, self, tree);
                        _ = try tree.writeNode(&left_sibling, false);
                        _ = try tree.writeNode(self, false);
                    } else {
                        try self.mergeChildren(i - 1, &left_sibling, &child, tree);
                        child = left_sibling;
                    }
                } else if (i < self.num_keys) {
                    var right_sibling: Self = try tree.readNode(self.children_offsets[i + 1]);
                    if (right_sibling.num_keys > MIN_KEYS) {
                        try child.borrowFromRight(i, &right_sibling, self, tree);
                        _ = try tree.writeNode(&right_sibling, false);
                        _ = try tree.writeNode(self, false);
                    } else {
                        try self.mergeChildren(i, &child, &right_sibling, tree);
                    }
                }
            }

            const deleted = try child.delete(key, tree);
            const new_offset = try tree.writeNode(&child, false);
            self.children_offsets[i] = new_offset;
            return deleted;
        }

        fn getPredecessor(self: *Self, i: usize, tree: *BTreeType) !struct { key: usize, value: u64 } {
            var cur = try tree.readNode(self.children_offsets[i]);
            while (!cur.is_leaf) {
                cur = try tree.readNode(cur.children_offsets[cur.num_keys]);
            }
            return .{ .key = cur.keys[cur.num_keys - 1], .value = cur.values[cur.num_keys - 1] };
        }

        fn getSuccessor(self: *Self, i: usize, tree: *BTreeType) !struct { key: usize, value: u64 } {
            var cur = try tree.readNode(self.children_offsets[i + 1]);
            while (!cur.is_leaf) {
                cur = try tree.readNode(cur.children_offsets[0]);
            }
            return .{ .key = cur.keys[0], .value = cur.values[0] };
        }

        pub fn deleteInLeafPath(self: *Self, key: usize, tree: *BTreeType) !bool {
            std.debug.assert(self.is_leaf);

            const idx = self.findKeyIndex(key);
            if (idx < self.num_keys and self.keys[idx] == key) {
                // shift left
                for (idx..self.num_keys - 1) |k| {
                    self.keys[k] = self.keys[k + 1];
                    self.values[k] = self.values[k + 1];
                }
                self.keys[self.num_keys - 1] = 0;
                self.values[self.num_keys - 1] = 0;
                self.num_keys -= 1;

                _ = try tree.writeNode(self, false); // <<-- false
                return true;
            }
            return false;
        }

        pub fn mergeChildren(
            self: *Self,
            i: usize,
            left: *Self,
            right: *Self,
            tree: *BTreeType,
        ) !void {
            // Move separator key from parent into left child
            left.keys[MIN_KEYS] = self.keys[i];
            left.values[MIN_KEYS] = self.values[i];

            // Copy right's keys and values into left
            for (right.keys[0..right.num_keys], 0..) |k, j| {
                left.keys[MIN_KEYS + 1 + j] = k;
                left.values[MIN_KEYS + 1 + j] = right.values[j];
            }

            // Copy right's children if not leaf
            if (!left.is_leaf) {
                for (right.children_offsets[0 .. right.num_keys + 1], 0..) |offset, j| {
                    left.children_offsets[MIN_KEYS + 1 + j] = offset;
                }
            }

            // Update number of keys in left
            left.num_keys += right.num_keys + 1;

            // Shift parent's keys and values left
            var j = i;
            while (j + 1 < self.num_keys) : (j += 1) {
                self.keys[j] = self.keys[j + 1];
                self.values[j] = self.values[j + 1];
                self.children_offsets[j + 1] = self.children_offsets[j + 2];
            }

            self.num_keys -= 1;

            // Clear dangling offset
            self.children_offsets[self.num_keys + 1] = 0; // Optional: 0 indicates unused

            // Write updated nodes
            const new_left_offset = try tree.writeNode(left, false);
            _ = try tree.writeNode(right, false); // Optionally, for consistency (or reuse)
            _ = try tree.writeNode(self, false);

            // Update parent's child pointer to new left
            self.children_offsets[i] = new_left_offset;

            // Optionally: mark `right` as reusable/freed (not shown here)
        }

        pub fn borrowFromLeft(
            self: *Self,
            i: usize,
            left: *Self,
            parent: *Self,
            tree: *BTreeType,
        ) !void {
            // Shift self's keys and values right
            var j = self.num_keys;
            while (j > 0) : (j -= 1) {
                self.keys[j] = self.keys[j - 1];
                self.values[j] = self.values[j - 1];
            }

            if (!self.is_leaf) {
                var k = self.num_keys + 1;
                while (k > 0) : (k -= 1) {
                    self.children_offsets[k] = self.children_offsets[k - 1];
                }
            }

            // Move key from parent to self
            self.keys[0] = parent.keys[i];
            self.values[0] = parent.values[i];
            if (!self.is_leaf) {
                self.children_offsets[0] = left.children_offsets[left.num_keys];
            }

            // Move last key of left to parent
            parent.keys[i] = left.keys[left.num_keys - 1];
            parent.values[i] = left.values[left.num_keys - 1];

            self.num_keys += 1;
            left.num_keys -= 1;

            // ✨ Write modified nodes back
            _ = try tree.writeNode(left, false);
            _ = try tree.writeNode(self, false);
            _ = try tree.writeNode(parent, false);
        }
        pub fn borrowFromRight(
            self: *Self, // Left child
            i: usize, // Index in parent
            right: *Self, // Right sibling
            parent: *Self, // Parent node
            tree: *BTreeType,
        ) !void {

            // Step 1: Move parent's separating key to self (append at the end)
            self.keys[self.num_keys] = parent.keys[i];
            self.values[self.num_keys] = parent.values[i];

            if (!self.is_leaf) {
                // Move the first child of right to self's child list
                self.children_offsets[self.num_keys + 1] = right.children_offsets[0];
            }

            // Step 2: Move right's first key to parent
            parent.keys[i] = right.keys[0];
            parent.values[i] = right.values[0];

            // Step 3: Shift right's keys and values left
            for (0..right.num_keys - 1) |j| {
                right.keys[j] = right.keys[j + 1];
                right.values[j] = right.values[j + 1];
            }

            if (!right.is_leaf) {
                // Shift right's children_offsets left
                for (0..right.num_keys) |j| {
                    right.children_offsets[j] = right.children_offsets[j + 1];
                }
            }

            // Step 4: Update key counts
            self.num_keys += 1;
            right.num_keys -= 1;

            // Step 5: Write all modified nodes
            _ = try tree.writeNode(right, false);
            _ = try tree.writeNode(self, false);
            _ = try tree.writeNode(parent, false);
        }
    };
}
