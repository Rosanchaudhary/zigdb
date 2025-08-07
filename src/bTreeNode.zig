// bTreeNode.zig
const std = @import("std");
const Record = @import("main.zig").Record;
const Ti = 2;
const MAX_KEYS = 2 * Ti - 1;
const MIN_KEYS = Ti - 1;
const MAX_CHILDREN = MAX_KEYS + 1;

pub const BTreeNode = struct {
    keys: [MAX_KEYS]usize,
    values: [MAX_KEYS]u64,
    children_offsets: [MAX_CHILDREN]u64,
    num_keys: u8,
    is_leaf: bool,

    pub fn init(is_leaf: bool) BTreeNode {
        return BTreeNode{
            .keys = [_]usize{0} ** MAX_KEYS,
            .values = [_]u64{0} ** MAX_KEYS,
            .children_offsets = [_]u64{0} ** MAX_CHILDREN,
            .num_keys = 0,
            .is_leaf = is_leaf,
        };
    }

    pub fn print(self: *const BTreeNode) void {
        std.debug.print("BTreeNode:\n", .{});
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

    pub fn traverseNodes(self: *const BTreeNode, tree: anytype) !void {
        std.debug.print("======= NODE =======\n", .{});
        self.print();

        if (!self.is_leaf) {
            for (self.children_offsets[0 .. self.num_keys + 1]) |offset| {
                const child = try tree.readNode(offset);
                try child.traverseNodes(tree);
            }
        }
    }

    pub fn insertNonFull(self: *BTreeNode, key: usize, record_offset: u64, tree: anytype) !void {
        var i = self.num_keys;

        if (self.is_leaf) {
            while (i > 0) : (i -= 1) {
                if (key >= self.keys[i - 1]) break;
                self.keys[i] = self.keys[i - 1];
                self.values[i] = self.values[i - 1];
            }
            self.keys[i] = key;
            self.values[i] = record_offset;
            self.num_keys += 1;

            _ = try tree.writeNode(self, true);
        } else {
            while (i > 0 and key < self.keys[i - 1]) : (i -= 1) {}
            var child = try tree.readNode(self.children_offsets[i]);
            if (child.num_keys == MAX_KEYS) {
                try self.splitChild(i, &child, tree);
                if (key > self.keys[i]) i += 1;
                child = try tree.readNode(self.children_offsets[i]);
            }
            try child.insertNonFull(key, record_offset, tree);
            const new_offset = try tree.writeNode(&child, false);
            self.children_offsets[i] = new_offset;
            _ = try tree.writeNode(self, true);
        }
    }

    pub fn splitChild(self: *BTreeNode, i: usize, y: *BTreeNode, tree: anytype) !void {
        var z = BTreeNode.init(y.is_leaf);
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

    pub fn traverse(self: *const BTreeNode, tree: anytype, allocator: std.mem.Allocator) ![]Record {
        var records = std.ArrayList(Record).init(allocator);

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

    pub fn search(self: *const BTreeNode, key: usize, tree: anytype) !?u64 {
        var i: usize = 0;
        while (i < self.num_keys and key > self.keys[i]) : (i += 1) {}

        if (i < self.num_keys and key == self.keys[i]) {
            return self.values[i]; // found, return record offset
        }

        if (self.is_leaf) {
            return null; // not found
        }

        const child = try tree.readNode(self.children_offsets[i]);
        return try child.search(key, tree);
    }

    pub fn deleteLeafOnly(self: *BTreeNode, key: usize, tree: anytype) !bool {
        var idx: usize = 0;

        // Find the key or the position where it should be
        while (idx < self.num_keys and self.keys[idx] < key) : (idx += 1) {}

        if (idx < self.num_keys and self.keys[idx] == key) {
            // ✅ Found the key
            if (!self.is_leaf) {
                // 🚫 For now, we only delete from leaf nodes
                std.debug.print("Key found in internal node, skipping deletion.\n", .{});
                return false;
            }

            // Shift keys/values left to remove the key
            for (idx..self.num_keys - 1) |i| {
                self.keys[i] = self.keys[i + 1];
                self.values[i] = self.values[i + 1];
            }

            // Clear last key/value
            self.keys[self.num_keys - 1] = 0;
            self.values[self.num_keys - 1] = 0;
            self.num_keys -= 1;

            // Write updated node to disk
            _ = try tree.writeNode(self, true);
            std.debug.print("Writing to the disk\n", .{});
            return true;
        }

        if (self.is_leaf) {
            // ❌ Key not found
            return false;
        }

        // 🔁 Recurse into the correct child
        const child_offset = self.children_offsets[idx];
        var child = try tree.readNode(child_offset);
        const deleted = try child.deleteLeafOnly(key, tree);

        const new_offset = try tree.writeNode(&child, false);
        self.children_offsets[idx] = new_offset;
        _ = try tree.writeNode(self, true);

        return deleted;
    }

    pub fn delete(self: *BTreeNode, key: usize, tree: anytype) !bool {
        std.debug.print("Printing internal node\n", .{});
        self.print();

        var i: usize = 0;
        while (i < self.num_keys and key > self.keys[i]) : (i += 1) {}

        if (i < self.num_keys and key == self.keys[i]) {
            // Key is in this internal node
            var left_child = try tree.readNode(self.children_offsets[i]);
            std.debug.print("Left child for key match:\n", .{});
            left_child.print();

            if (left_child.num_keys >= Ti) {
                // Use predecessor
                const pred_key = left_child.keys[left_child.num_keys - 1];
                const pred_offset = left_child.values[left_child.num_keys - 1];

                self.keys[i] = pred_key;
                self.values[i] = pred_offset;
                _ = try tree.writeNode(self, true);

                const deleted = try left_child.deleteLeafOnly(pred_key, tree);
                const left_offset = try tree.writeNode(&left_child, false);
                self.children_offsets[i] = left_offset;
                return deleted;
            }

            var right_child = try tree.readNode(self.children_offsets[i + 1]);
            std.debug.print("Right child for key match:\n", .{});
            right_child.print();

            if (right_child.num_keys >= Ti) {
                // Use successor
                const succ_key = right_child.keys[0];
                const succ_offset = right_child.values[0];

                self.keys[i] = succ_key;
                self.values[i] = succ_offset;
                _ = try tree.writeNode(self, true);

                const deleted = try right_child.deleteLeafOnly(succ_key, tree);
                const right_offset = try tree.writeNode(&right_child, false);
                self.children_offsets[i + 1] = right_offset;
                return deleted;
            }

            // Both children have MIN_KEYS, merge and delete from merged node
            std.debug.print("Merging both children because both have MIN_KEYS\n", .{});
            try self.mergeChildren(i, &left_child, &right_child, tree);
            const deleted = try left_child.delete(key, tree);
            const new_offset = try tree.writeNode(&left_child, false);
            self.children_offsets[i] = new_offset;
            return deleted;
        }

        // Key is not in this node
        if (!self.is_leaf) {
            std.debug.print("Key not in internal node, descending to child {}\n", .{i});
            var child = try tree.readNode(self.children_offsets[i]);

            // Check for underflow
            if (child.num_keys == MIN_KEYS) {
                if (i > 0) {
                    var left_sibling = try tree.readNode(self.children_offsets[i - 1]);
                    if (left_sibling.num_keys > MIN_KEYS) {
                        std.debug.print("Borrowing from left sibling\n", .{});
                        try child.borrowFromLeft(i - 1, &left_sibling, self, tree);
                        _ = try tree.writeNode(&left_sibling, false);
                        _ = try tree.writeNode(self, true);
                    } else {
                        std.debug.print("Merging with left sibling\n", .{});
                        try self.mergeChildren(i - 1, &left_sibling, &child, tree);
                        child = left_sibling;
                        i -= 1;
                    }
                } else if (i < self.num_keys) {
                    var right_sibling = try tree.readNode(self.children_offsets[i + 1]);
                    if (right_sibling.num_keys > MIN_KEYS) {
                        std.debug.print("Borrowing from right sibling\n", .{});
                        try child.borrowFromRight(i, &right_sibling, self, tree);
                        _ = try tree.writeNode(&right_sibling, false);
                        _ = try tree.writeNode(self, true);
                    } else {
                        std.debug.print("Merging with right sibling\n", .{});
                        try self.mergeChildren(i, &child, &right_sibling, tree);
                    }
                }
            }

            const deleted = try child.delete(key, tree);
            const new_offset = try tree.writeNode(&child, false);
            self.children_offsets[i] = new_offset;
            return deleted;
        }

        return false; // key not found in a leaf node
    }

    pub fn mergeChildren(
        self: *BTreeNode,
        i: usize,
        left: *BTreeNode,
        right: *BTreeNode,
        tree: anytype,
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
        self: *BTreeNode,
        i: usize,
        left: *BTreeNode,
        parent: *BTreeNode,
        tree: anytype,
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
        self: *BTreeNode,
        i: usize,
        right: *BTreeNode,
        parent: *BTreeNode,
        tree: anytype,
    ) !void {
        // Move key from parent to self
        self.keys[self.num_keys] = parent.keys[i];
        self.values[self.num_keys] = parent.values[i];
        if (!self.is_leaf) {
            self.children_offsets[self.num_keys + 1] = right.children_offsets[0];
        }

        // Move first key from right to parent
        parent.keys[i] = right.keys[0];
        parent.values[i] = right.values[0];

        // Shift right's keys and values left
        for (0..right.num_keys - 1) |j| {
            right.keys[j] = right.keys[j + 1];
            right.values[j] = right.values[j + 1];
        }
        if (!right.is_leaf) {
            for (0..right.num_keys) |j| {
                right.children_offsets[j] = right.children_offsets[j + 1];
            }
        }

        self.num_keys += 1;
        right.num_keys -= 1;

        // ✨ Write modified nodes back
        _ = try tree.writeNode(right, false);
        _ = try tree.writeNode(self, false);
        _ = try tree.writeNode(parent, false);
    }
};
