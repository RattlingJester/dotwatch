const std = @import("std");

const Self = @This();

tracked: []const [:0]const u8 = undefined,
ignore: []const [:0]const u8 = undefined,
repo: [:0]const u8 = undefined,

pub fn parse(
    alloc: std.mem.Allocator,
    arena: std.mem.Allocator,
    contents: [:0]const u8,
) !Self {
    var diagnostics: std.zon.parse.Diagnostics = .{ .errors = undefined };

    const parsed = std.zon.parse.fromSlice(Self, .{
        .gpa = alloc,
        .arena = arena,
        .source = contents,
        .diagnostics = &diagnostics,
    }) catch |err| {
        diagnostics.fatal("config.zon");

        return err;
    };

    return parsed;
}
