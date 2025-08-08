const std = @import("std");
const Btree = @import("bTree.zig").Btree;

pub const Record = struct { id: usize, name: []const u8, email: []const u8, address: []const u8 };

pub fn main() !void {
    var tree = try Btree(Record).init();
    defer tree.deinit();

    try tree.insert(.{ .id = 1, .name = "alice", .email = "alice@example.com", .address = "home" });
    try tree.insert(.{ .id = 2, .name = "bob", .email = "bob@example.com", .address = "home" });
    try tree.insert(.{ .id = 3, .name = "carol", .email = "carol@example.com", .address = "home" });
    try tree.insert(.{ .id = 4, .name = "dave", .email = "dave@example.com", .address = "home" });
    try tree.insert(.{ .id = 5, .name = "eve", .email = "eve@example.com", .address = "home" });

    std.debug.print("Inserted records.\n", .{});
    try tree.traverseAllNodes();
    // const dataList = try tree.traverse();
    // for (dataList) |value| {
    //     std.debug.print("Id: {d}, Name: {s}, Email: {s} , Address:{s}\n", .{ value.id, value.name, value.email, value.address });
    // }

    // const result = try tree.search(1);
    // if (result) |record| {
    //     std.debug.print(" Name: {s}, Email: {s} , Address:{s}\n", .{ record.name, record.email, record.address });
    // } else {
    //     std.debug.print("Not found.\n", .{});
    // }

    const deleteIndex: usize = 5;

    const deleted = try tree.delete(deleteIndex);
    if (deleted) {
        std.debug.print("Deleted key {d} from internal node.\n", .{deleteIndex});
    } else {
        std.debug.print("Key {d} not deleted.\n", .{deleteIndex});
    }
    std.debug.print("After deletion records.+++++++++++++++++++++++++++=\n", .{});
    try tree.traverseAllNodes();

    const newList = try tree.traverse();
    for (newList) |value| {
        std.debug.print("Id: {d}, Name: {s}, Email: {s} , Address:{s}\n", .{ value.id, value.name, value.email, value.address });
    }
}
