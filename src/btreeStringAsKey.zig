const std = @import("std");

pub const T: usize = 3; // minimum degree
pub const MAX_KEYS: usize = 2 * T - 1;
pub const MIN_KEYS: usize = T - 1;
pub const MAX_CHILDREN: usize = 2 * T;

const Node = struct {
    keys: [MAX_KEYS][]const u8,
    children: [MAX_CHILDREN]?*Node,
    num_keys: usize,
    is_leaf: bool,

    fn init(is_leaf: bool) !Node {
        return Node{
            .keys = undefined,
            .children = [_]?*Node{null} ** 6,
            .num_keys = 0,
            .is_leaf = is_leaf,
        };
    }

    /// Split the full child `y = parent.children[i]` into two nodes,
    /// promoting its middle key into the parent.
    ///
    /// After this:
    /// - The parent will gain one extra key
    /// - `y` will contain the left half of the keys
    /// - A new node `z` will contain the right half of the keys
    fn splitChild(parent: *Node, i: usize, allocator: *std.mem.Allocator) !void {
        // `y` is the child that is currently full
        const y = parent.children[i].?;

        // Allocate a new node `z` which will store the right half of `y`
        var z = try allocator.create(Node);
        z.* = try Node.init(y.is_leaf);

        // `z` will get T - 1 keys (the right half of y)
        z.num_keys = T - 1;

        // Copy the last T-1 keys of `y` into `z`
        var j: usize = 0;
        while (j < T - 1) : (j += 1) {
            z.keys[j] = y.keys[j + T];
        }

        // If `y` is not a leaf, copy its last T children into `z`
        if (!y.is_leaf) {
            j = 0;
            while (j < T) : (j += 1) {
                z.children[j] = y.children[j + T];
            }
        }

        // Reduce the number of keys in `y` (it now holds only the left half)
        y.num_keys = T - 1;

        // Shift parent's children rightward to make space for the new child
        var k: usize = parent.num_keys + 1;
        while (k > i + 1) : (k -= 1) {
            parent.children[k] = parent.children[k - 1];
        }
        parent.children[i + 1] = z; // place new child to the right of `y`

        // Shift parent's keys rightward to make space for the promoted key
        k = parent.num_keys;
        while (k > i) : (k -= 1) {
            parent.keys[k] = parent.keys[k - 1];
        }

        // Promote the middle key from `y` into the parent
        parent.keys[i] = y.keys[T - 1];
        parent.num_keys += 1;
    }

    /// Insert a key into a node that is guaranteed to be non-full.
    /// This function either inserts directly into a leaf or descends into the correct child.
    fn insertNonFull(self: *Node, key: []const u8, allocator: *std.mem.Allocator) !void {
        // Start from the number of keys in this node
        var i: usize = self.num_keys;

        // Case 1: This node is a leaf → just insert the key here
        if (self.is_leaf) {
            // Shift keys one position to the right until we find the correct place for `key`
            // Keep moving larger keys to the right
            while (i > 0 and std.mem.order(u8, key, self.keys[i - 1]) == .lt) {
                self.keys[i] = self.keys[i - 1];
                i -= 1;
            }

            // Place the new key at its sorted position
            self.keys[i] = key;
            self.num_keys += 1;
        } else {
            // Case 2: Internal node → we must descend into the correct child

            // Find the first key that is greater than or equal to `key`.
            // The correct child is the one just before or equal to that key.
            var idx: usize = 0;
            while (idx < self.num_keys and std.mem.order(u8, key, self.keys[idx]) == .gt) {
                idx += 1;
            }

            // At this point, `idx` is the child we want to descend into.

            // If the chosen child is full, split it before descending
            const child = self.children[idx].?;
            if (child.num_keys == MAX_KEYS) {
                // Split child[idx] into two children and promote its middle key
                try self.splitChild(idx, allocator);

                // After splitting, decide whether the key belongs
                // in the left child (idx) or the new right child (idx + 1).
                if (std.mem.order(u8, key, self.keys[idx]) == .gt) {
                    idx += 1;
                }
            }

            // Now insert the key into the correct child (which is guaranteed to be non-full)
            try self.children[idx].?.insertNonFull(key, allocator);
        }
    }

    fn search(self: *Node, key: []const u8) ?*Node {
        var i: usize = 0;

        //move forward while key is greater than current key
        while (i < self.num_keys and std.mem.order(u8, key, self.keys[i]) == .gt) : (i += 1) {}

        //if key equal ones stored here, return this node
        if (i < self.num_keys and std.mem.order(u8, key, self.keys[i]) == .eq) {
            return self;
        }

        //if this is a leaf, we didn't find it
        if (self.is_leaf) return null;

        //otherwise, recure into the proper child
        if (self.children[i]) |child| {
            return child.search(key);
        } else {
            return null;
        }
    }

    /// Traverse the B-Tree rooted at this node and print all keys in sorted order.
    /// This uses in-order traversal:
    ///   - Visit child[i]
    ///   - Print key[i]
    ///   - Repeat until all keys and children are visited
    fn traverse(self: *Node) void {
        var i: usize = 0;

        // Go through all keys one by one
        while (i < self.num_keys) : (i += 1) {
            // If not a leaf, visit the left child before printing the key
            if (!self.is_leaf) {
                if (self.children[i]) |child| {
                    child.traverse();
                }
            }

            // Print the key after its left subtree
            std.debug.print("{s} ", .{self.keys[i]});
        }

        // After the last key, visit the rightmost child
        if (!self.is_leaf) {
            if (self.children[i]) |child| {
                child.traverse();
            }
        }
    }
};

const BTree = struct {
    root: ?*Node,
    allocator: *std.mem.Allocator,

    pub fn init(allocator: *std.mem.Allocator) BTree {
        return BTree{
            .root = null,
            .allocator = allocator,
        };
    }

    pub fn search(self: *BTree, key: []const u8) ?*Node {
        if (self.root) |r| {
            return r.search(key);
        }
        return null;
    }

    /// Insert a key into the B-Tree
    pub fn insert(self: *BTree, key: []const u8) !void {
        // Case 1: The tree is empty -> create a root node
        if (self.root == null) {
            // Allocate memory for a new root node
            var root = try self.allocator.create(Node);
            // Initialize it as a leaf node
            root.* = try Node.init(true);
            // Put the first key directly into this root
            root.keys[0] = key;
            root.num_keys = 1;
            // Assign this node as the root of the tree
            self.root = root;
            return;
        }

        // Otherwise, the tree already has a root
        var r = self.root.?;

        // Case 2: If the root is full, it must be split
        if (r.num_keys == MAX_KEYS) {
            // Create a new root (non-leaf), which will replace the old one
            var new_root = try self.allocator.create(Node);
            new_root.* = try Node.init(false);

            // Old root becomes child[0] of the new root
            new_root.children[0] = r;

            // Split the old root into two nodes and move the middle key up
            try new_root.splitChild(0, self.allocator);

            // Make sure the tree’s root pointer is updated
            self.root = new_root;

            // Decide which of the two children should get the new key
            const idx: usize = if (std.mem.order(u8, key, new_root.keys[0]) == .gt)
                1 // go right if key > promoted key
            else
                0; // otherwise go left

            // Insert the new key into the correct child (which is guaranteed to be non-full now)
            try new_root.children[idx].?.insertNonFull(key, self.allocator);
        } else {
            // Case 3: If root is not full, just insert normally
            try r.insertNonFull(key, self.allocator);
        }
    }

    /// Traverse the entire B-Tree starting from the root.
    /// If the tree is empty, print a message instead.
    pub fn traverse(self: *BTree) void {
        if (self.root) |r| {
            r.traverse();
            std.debug.print("\n", .{});
        } else {
            std.debug.print("(empty tree)\n", .{});
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.page_allocator;
    var tree = BTree.init(&gpa);

    try tree.insert("delta");
    try tree.insert("alpha");
    try tree.insert("charlie");
    try tree.insert("bravo");
    try tree.insert("gamma");
    try tree.insert("relta");
    try tree.insert("tiger");
    try tree.insert("liok");

    if (tree.search("liok")) |found| {
        std.debug.print("Found king in node with {d} keys\n", .{found.num_keys});
    } else {
        std.debug.print("Not found\n", .{});
    }

    std.debug.print("Tree traversal: ", .{});
    tree.traverse();
}
