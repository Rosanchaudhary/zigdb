// bTreeNode.zig
const std = @import("std");
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

    pub fn insertNonFull(self: *BTreeNode, key: usize, record_offset: u64, tree: anytype) !void {
        var i = self.num_keys;
        if (self.is_leaf) {
            std.debug.print("Inserting in leaf \n", .{});
            while (i > 0) : (i -= 1) {
                if (key >= self.keys[i - 1]) break;
                self.keys[i] = self.keys[i - 1];
                self.values[i] = self.values[i - 1];
            }
            self.keys[i] = key;
            self.values[i] = record_offset;
            self.num_keys += 1;
            _ = try tree.writeNode(self);
        } else {
            while (i > 0 and key < self.keys[i - 1]) : (i -= 1) {}
            var child = try tree.readNode(self.children_offsets[i]);
            if (child.num_keys == MAX_KEYS) {
                try self.splitChild(i, &child, tree);
                if (key > self.keys[i]) i += 1;
                child = try tree.readNode(self.children_offsets[i]);
            }
            try child.insertNonFull(key, record_offset, tree);
            const new_offset = try tree.writeNode(&child);
            self.children_offsets[i] = new_offset;
            _ = try tree.writeNode(self);
        }
    }

    pub fn splitChild(self: *BTreeNode, i: usize, y: *BTreeNode, tree: anytype) !void {
        var z = BTreeNode.init(y.is_leaf);
        z.num_keys = MIN_KEYS;

        for (MIN_KEYS..MAX_KEYS) |j| {
            z.keys[j - MIN_KEYS] = y.keys[j];
            z.values[j - MIN_KEYS] = y.values[j];
        }

        if (!y.is_leaf) {
            for (MIN_KEYS + 1..MAX_CHILDREN) |j| {
                z.children_offsets[j - (MIN_KEYS + 1)] = y.children_offsets[j];
            }
        }

        y.num_keys = MIN_KEYS;

        var j = self.num_keys;
        while (j > i) : (j -= 1) self.children_offsets[j + 1] = self.children_offsets[j];
        const z_offset = try tree.writeNode(&z);
        self.children_offsets[i + 1] = z_offset;

        j = self.num_keys;
        while (j > i) : (j -= 1) {
            self.keys[j] = self.keys[j - 1];
            self.values[j] = self.values[j - 1];
        }

        self.keys[i] = y.keys[MIN_KEYS];
        self.values[i] = y.values[MIN_KEYS];
        self.num_keys += 1;

        const y_offset = try tree.writeNode(y);
        self.children_offsets[i] = y_offset;
        _ = try tree.writeNode(self);
    }

    pub fn traverse(self: *const BTreeNode, tree: anytype) !void {
        var i: usize = 0;
        while (i < self.num_keys) {
            if (!self.is_leaf) {
                const child = try tree.readNode(self.children_offsets[i]);
                try child.traverse(tree);
            }

            const record = try tree.readRecord(self.values[i]);
            std.debug.print("Key: {}, Name: {s}, Email: {s}\n", .{
                self.keys[i], record.name, record.email,
            });
            i += 1;
        }
        if (!self.is_leaf) {
            const child = try tree.readNode(self.children_offsets[i]);
            try child.traverse(tree);
        }
    }
};
