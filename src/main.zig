const std = @import("std");

const Ti = 2;
pub const MAX_KEYS = 2 * Ti - 1;
const MIN_KEYS = Ti - 1;

fn BTreeNode(comptime B: type, comptime V: type) type {
    return struct {
        const Self = @This();

        keys: [MAX_KEYS]B,
        values: [MAX_KEYS]V,
        children: [MAX_KEYS + 1]?*Self,
        num_keys: u8,
        is_leaf: bool,

        pub fn init(is_leaf: bool) Self {
            return Self{
                .keys = undefined,
                .values = undefined,
                .children = [_]?*Self{null} ** (MAX_KEYS + 1),
                .num_keys = 0,
                .is_leaf = is_leaf,
            };
        }

        pub fn deinit(self: *Self) void {
            if (!self.is_leaf) {
                var i: usize = 0;
                while (i <= self.num_keys) : (i += 1) {
                    if (self.children[i]) |child| {
                        child.deinit();
                        std.heap.page_allocator.destroy(child);
                    }
                }
            }
            // The current node will be destroyed by the caller (Btree or parent).
        }

        pub fn insert(self: *Self, key: B, value: V) void {
            var i: i32 = @as(i32, self.num_keys) - 1;

            if (self.is_leaf) {
                // Shift keys to make space
                while (i >= 0 and self.keys[@as(usize, @intCast(i))] > key) : (i -= 1) {
                    const idx = @as(usize, @intCast(i));
                    self.keys[idx + 1] = self.keys[idx];
                    self.values[idx + 1] = self.values[idx];
                }
                const idx = @as(usize, @intCast(i + 1));
                self.keys[idx] = key;
                self.values[idx] = value;
                self.num_keys += 1;
            } else {
                // Find correct child
                while (i >= 0 and self.keys[@as(usize, @intCast(i))] > key) : (i -= 1) {}

                const child_idx = @as(usize, @intCast(i + 1));
                var child = self.children[child_idx].?;

                if (child.num_keys == MAX_KEYS) {
                    self.splitChild(child_idx, child);

                    if (self.keys[child_idx] < key) {
                        child = self.children[child_idx + 1].?;
                    }
                }
                child.insert(key, value);
            }
        }

        fn splitChild(self: *Self, i: usize, y: *Self) void {
            const allocator = std.heap.page_allocator;
            var z = allocator.create(Self) catch unreachable;
            z.* = Self.init(y.is_leaf);
            z.num_keys = MIN_KEYS;

            // Copy last MIN_KEYS keys and values from y to z
            var j: usize = 0;
            while (j < MIN_KEYS) : (j += 1) {
                z.keys[j] = y.keys[j + Ti];
                z.values[j] = y.values[j + Ti];
            }

            // If y is not a leaf, move y's last Ti children to z
            if (!y.is_leaf) {
                j = 0;
                while (j <= MIN_KEYS) : (j += 1) {
                    z.children[j] = y.children[j + Ti];
                }
            }

            y.num_keys = MIN_KEYS;

            // Shift self.children to make space for z
            var j_child = self.num_keys;
            while (j_child >= i + 1) : (j_child -= 1) {
                self.children[j_child + 1] = self.children[j_child];
                if (j_child == 0) break;
            }
            self.children[i + 1] = z;

            // Shift keys and values to make space for y's middle key
            var j_key = self.num_keys;
            while (j_key > i) : (j_key -= 1) {
                self.keys[j_key] = self.keys[j_key - 1];
                self.values[j_key] = self.values[j_key - 1];
            }
            self.keys[i] = y.keys[MIN_KEYS];
            self.values[i] = y.values[MIN_KEYS];

            self.num_keys += 1;
        }

        pub fn traverse(self: *Self) void {
            var i: usize = 0;
            while (i < self.num_keys) : (i += 1) {
                if (!self.is_leaf) {
                    if (self.children[i]) |child| {
                        child.traverse();
                    }
                }
                std.debug.print("Key: {}, Record(id: {}, name: {s}, email: {s})\n", .{
                    self.keys[i],
                    self.values[i].id,
                    self.values[i].name,
                    self.values[i].email,
                });
            }
            if (!self.is_leaf) {
                if (self.children[i]) |child| {
                    child.traverse();
                }
            }
        }

        pub fn search(self: *Self, key: B) ?V {
            var i: usize = 0;

            // Find the first key greater than or equal to `key`
            while (i < self.num_keys and key > self.keys[i]) : (i += 1) {}

            // If the key is found, return this node
            if (i < self.num_keys and self.keys[i] == key) {
                return self.values[i];
            }

            // If it's a leaf, the key is not present
            if (self.is_leaf) {
                return null;
            }

            // Otherwise, search in the appropriate child
            return self.children[i].?.search(key);
        }

        pub fn remove(self: *Self, key: B) void {
            var idx: usize = 0;

            // Find the key's position in the node
            while (idx < self.num_keys and key > self.keys[idx]) : (idx += 1) {}

            if (idx < self.num_keys and self.keys[idx] == key) {
                if (self.is_leaf) {
                    self.removeFromLeaf(idx);
                } else {
                    self.removeFromInternal(idx);
                }
            } else {
                if (self.is_leaf) return; // Key not found

                const child = self.children[idx].?;

                // Ensure child has enough keys before going deeper
                if (child.num_keys == MIN_KEYS) {
                    self.fillChild(idx);

                    if (idx >= self.num_keys + 1) {
                        // idx was the last child, and merge moved it left.
                        self.children[idx - 1].?.remove(key);
                        return;
                    }
                }

                self.children[idx].?.remove(key);
            }
        }

        fn removeFromLeaf(self: *Self, idx: usize) void {
            for (idx..self.num_keys - 1) |j| {
                self.keys[j] = self.keys[j + 1];
                self.values[j] = self.values[j + 1];
            }
            self.num_keys -= 1;
        }

        fn removeFromInternal(self: *Self, idx: usize) void {
            var child = self.children[idx].?;
            var sibling = self.children[idx + 1].?;

            if (child.num_keys > MIN_KEYS) {
                const pred_key = self.getPredecessorKey(idx);
                const pred_value = self.getPredecessorValue(idx);

                self.keys[idx] = pred_key;
                self.values[idx] = pred_value;

                child.remove(pred_key);
            } else if (sibling.num_keys > MIN_KEYS) {
                const succ_key = self.getSuccessorKey(idx);
                const succ_value = self.getSuccessorValue(idx);

                self.keys[idx] = succ_key;
                self.values[idx] = succ_value;

                sibling.remove(succ_key);
            } else {
                self.mergeChildren(idx);
                self.children[idx].?.remove(self.keys[idx]);
            }
        }

        fn getPredecessorKey(self: *Self, idx: usize) B {
            var curr = self.children[idx].?;
            while (!curr.is_leaf) {
                curr = curr.children[curr.num_keys].?;
            }
            return curr.keys[curr.num_keys - 1];
        }

        fn getPredecessorValue(self: *Self, idx: usize) V {
            var curr = self.children[idx].?;
            while (!curr.is_leaf) {
                curr = curr.children[curr.num_keys].?;
            }
            return curr.values[curr.num_keys - 1];
        }

        fn getSuccessorKey(self: *Self, idx: usize) B {
            var curr = self.children[idx + 1].?;
            while (!curr.is_leaf) {
                curr = curr.children[0].?;
            }
            return curr.keys[0];
        }

        fn getSuccessorValue(self: *Self, idx: usize) V {
            var curr = self.children[idx + 1].?;
            while (!curr.is_leaf) {
                curr = curr.children[0].?;
            }
            return curr.values[0];
        }

        fn fillChild(self: *Self, idx: usize) void {
            if (idx > 0 and self.children[idx - 1].?.num_keys > MIN_KEYS) {
                self.borrowFromPrev(idx);
            } else if (idx < self.num_keys and self.children[idx + 1].?.num_keys > MIN_KEYS) {
                self.borrowFromNext(idx);
            } else {
                if (idx < self.num_keys) {
                    self.mergeChildren(idx);
                } else {
                    self.mergeChildren(idx - 1);
                }
            }
        }
        fn borrowFromPrev(self: *Self, idx: usize) void {
            var child = self.children[idx].?;
            var sibling = self.children[idx - 1].?;

            // Shift keys and values right
            for (0..child.num_keys) |i| {
                child.keys[i + 1] = child.keys[i];
                child.values[i + 1] = child.values[i];
            }

            // Shift children right if not leaf
            if (!child.is_leaf) {
                for (0..child.num_keys + 1) |i| {
                    child.children[i + 1] = child.children[i];
                }
            }

            // Move key and value from parent
            child.keys[0] = self.keys[idx - 1];
            child.values[0] = self.values[idx - 1];

            // Move key and value from sibling to parent
            self.keys[idx - 1] = sibling.keys[sibling.num_keys - 1];
            self.values[idx - 1] = sibling.values[sibling.num_keys - 1];

            // Move last child pointer from sibling to child if needed
            if (!sibling.is_leaf) {
                child.children[0] = sibling.children[sibling.num_keys];
            }

            child.num_keys += 1;
            sibling.num_keys -= 1;
        }

        fn borrowFromNext(self: *Self, idx: usize) void {
            var child = self.children[idx].?;
            var sibling = self.children[idx + 1].?;

            // Bring down key and value from parent
            child.keys[child.num_keys] = self.keys[idx];
            child.values[child.num_keys] = self.values[idx];

            // If child is not a leaf, take sibling's first child pointer
            if (!child.is_leaf) {
                child.children[child.num_keys + 1] = sibling.children[0];
            }

            // Replace parent key/value with sibling's first key/value
            self.keys[idx] = sibling.keys[0];
            self.values[idx] = sibling.values[0];

            // Shift keys, values, and children left in sibling
            for (1..sibling.num_keys) |i| {
                sibling.keys[i - 1] = sibling.keys[i];
                sibling.values[i - 1] = sibling.values[i];
            }
            if (!sibling.is_leaf) {
                for (1..sibling.num_keys + 1) |i| {
                    sibling.children[i - 1] = sibling.children[i];
                }
            }

            child.num_keys += 1;
            sibling.num_keys -= 1;
        }

        fn mergeChildren(self: *Self, idx: usize) void {
            var child = self.children[idx].?;
            const sibling = self.children[idx + 1].?;

            // Move key and value from parent into child
            child.keys[MIN_KEYS] = self.keys[idx];
            child.values[MIN_KEYS] = self.values[idx];

            // Copy keys and values from sibling
            for (0..sibling.num_keys) |i| {
                child.keys[i + MIN_KEYS + 1] = sibling.keys[i];
                child.values[i + MIN_KEYS + 1] = sibling.values[i];
            }

            // Copy children if not leaf
            if (!child.is_leaf) {
                for (0..sibling.num_keys + 1) |i| {
                    child.children[i + MIN_KEYS + 1] = sibling.children[i];
                }
            }

            // Shift parent keys, values, and children left
            for (idx..self.num_keys - 1) |i| {
                self.keys[i] = self.keys[i + 1];
                self.values[i] = self.values[i + 1];
                self.children[i + 1] = self.children[i + 2];
            }

            child.num_keys += sibling.num_keys + 1;
            self.num_keys -= 1;
        }
    };
}

pub fn Btree(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const BTreeNodeK = BTreeNode(K, V);
        root: ?*BTreeNodeK,

        pub fn init() Self {
            const node = std.heap.page_allocator.create(BTreeNodeK) catch unreachable;
            node.* = BTreeNodeK.init(true);
            return Self{ .root = node };
        }

        pub fn deinit(self: *Self) void {
            if (self.root) |root_node| {
                root_node.deinit();
                std.heap.page_allocator.destroy(root_node);
                self.root = null;
            }
        }

        pub fn insert(self: *Self, key: K, value: V) void {
            if (self.root) |r| {
                if (r.num_keys == MAX_KEYS) {
                    var s = std.heap.page_allocator.create(BTreeNodeK) catch unreachable;
                    s.* = BTreeNodeK.init(false);
                    s.children[0] = r;
                    s.splitChild(0, r);
                    s.insert(key, value);
                    self.root = s;
                } else {
                    r.insert(key, value);
                }
            } else {
                const node = std.heap.page_allocator.create(BTreeNodeK) catch unreachable;
                node.* = BTreeNodeK.init(true);
                node.insert(key, value);
                self.root = node;
            }
        }

        pub fn traverse(self: *Self) void {
            if (self.root) |root| {
                root.traverse();
                std.debug.print("\n", .{});
            }
        }

        pub fn searchTree(self: *Self, key: K) ?V {
            if (self.root) |root| {
                return root.search(key);
            }
            return null;
        }

        pub fn remove(self: *Self, key: K) void {
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

const Record = struct { id: usize, name: []const u8, email: []const u8 };

pub fn main() void {
    var tree = Btree(usize, Record).init();
    defer tree.deinit();

    tree.insert(1, .{ .id = 101, .name = "alice", .email = "alice@example.com" });
    tree.insert(2, .{ .id = 102, .name = "bob", .email = "bob@example.com" });
    tree.insert(3, .{ .id = 103, .name = "carol", .email = "carol@example.com" });
    tree.insert(4, .{ .id = 104, .name = "dave", .email = "dave@example.com" });
    tree.insert(5, .{ .id = 105, .name = "eve", .email = "eve@example.com" });
    tree.insert(6, .{ .id = 106, .name = "frank", .email = "frank@example.com" });
    tree.insert(7, .{ .id = 107, .name = "grace", .email = "grace@example.com" });
    tree.insert(8, .{ .id = 108, .name = "heidi", .email = "heidi@example.com" });
    tree.insert(9, .{ .id = 109, .name = "ivan", .email = "ivan@example.com" });
    tree.insert(10, .{ .id = 110, .name = "judy", .email = "judy@example.com" });

    std.debug.print("BTree contents (sorted order):\n", .{});
    tree.traverse();

    if (tree.searchTree(2)) |record| {
        std.debug.print("Found: id :{}, name:{s},email:{s}\n", .{ record.id, record.name, record.email });
    } else {
        std.debug.print("Not found.\n", .{});
    }

    tree.remove(1);
    if (tree.searchTree(2)) |record| {
        std.debug.print("Found: id :{}, name:{s},email:{s}\n", .{ record.id, record.name, record.email });
    } else {
        std.debug.print("Not found.\n", .{});
    }
    std.debug.print("\nAfter deleting 17:\n", .{});
    std.debug.print("BTree contents (sorted order):\n", .{});
    tree.traverse();
}
