const std = @import("std");

const config = @import("config.zig");

const CONFIG_PATH = "/.config/dotwatch/config.toml";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const env_map = init.environ_map;
    const home = env_map.get("HOME") orelse return error.HomeNotFound;

    const path = try std.fs.path.join(gpa, &.{ home, CONFIG_PATH });
    const file = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
    gpa.free(path); // Path not needed anymore

    var conf = try config.parse(gpa, file);
    defer conf.deinit(gpa);

    gpa.free(file); // Whole file not needed anymore

    std.debug.print("Repo: {s}\n", .{conf.repo});
    for (conf.tracked.items) |item| {
        std.debug.print("Tracked (Offset {d}): {s}\n", .{ item.offset, item.value });
    }
}
