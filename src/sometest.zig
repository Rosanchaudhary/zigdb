pub fn deleteTest(self: *Self, key: usize) !bool {
    var root = try self.readNode(self.header.root_node_offset);
    const deleted = try root.delete(key, self);
    if (!deleted) return false;
    return true;
}

pub fn deleteLeafOnly(self: *Self, key: usize) !bool {
    var root = try self.readNode(self.header.root_node_offset);
    const deleted = try root.deleteInternal(key, self);

    if (deleted) {
        std.debug.print("Deleted key {d} from B-tree (leaf-only).\n", .{key});
        _ = try self.writeNode(&root, true);
        return true;
    } else {
        std.debug.print("Key {d} not found or not in a leaf.\n", .{key});
        return false;
    }
}
   pub fn deleteTest(self: *BTreeNode, key: usize, tree: anytype) !bool {
        var idx: usize = 0;
        while (idx < self.num_keys and self.keys[idx] < key) : (idx += 1) {}
        std.debug.print(" idx :{d} self num keys {d} self key[idx] {d} key {d}\n", .{ idx, self.num_keys, self.keys[idx], key });
        if (idx < self.num_keys and self.keys[idx] == key) {
            std.debug.print("Printing the node found in delete\n", .{});
            self.print();
            if (!self.is_leaf) {
                std.debug.print("Key found in internal node, skipping deletion.\n", .{});
                return false;
            }
            //shift key value left to remove the key
            for (idx..self.num_keys - 1) |i| {
                self.keys[i] = self.keys[i + 1];
                self.values[i] = self.values[i + 1];
            }
            //clear last key value
            self.keys[self.num_keys - 1] = 0;
            self.values[self.num_keys - 1] = 0;
            self.num_keys -= 1;
            std.debug.print("writing to file \n", .{});
            _ = try tree.writeNode(self, true);
            return true;
        }
        // ✅ Found the key
        if (!self.is_leaf) {
            // 🚫 For now, we only delete from leaf nodes
            std.debug.print("Key found in internal node, skipping deletion.\n", .{});
            return false;
        }
        // 🔁 Recurse into the correct child
        const child_offset = self.children_offsets[idx];
        var child = try tree.readNode(child_offset);
        const deleted = try child.delete(key, tree);

        const new_offset = try tree.writeNode(&child, false);
        self.children_offsets[idx] = new_offset;
        _ = try tree.writeNode(self, true);

        return deleted;
    }