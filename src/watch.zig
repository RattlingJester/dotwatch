const std = @import("std");

const Self = @This();
const StateMap = std.StringHashMap(i128);

map: StateMap,

pub fn init(alloc: std.mem.Allocator, config_path: []const u8) !Self {
    _ = alloc; // autofix
    _ = config_path; // autofix
}

pub fn deinit(self: *Self) void {
    self.map.deinit();
}

pub fn store(self: *const Self, io: std.Io) !void {
    _ = self; // autofix
    _ = io; // autofix
}
