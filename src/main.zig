const std = @import("std");
const builtin = @import("builtin");

const watch = @import("watch.zig");
const config = @import("config.zig");
const git = @import("git_wrapper.zig");

pub const std_options = std.Options{ .logFn = log, .log_level = .info };

const CONFIG_DIR = switch (builtin.target.os.tag) {
    .windows => "./", // Use program folder for windows
    .linux => ".config/dotwatch/",
    else => @compileError("OS not supported"),
};
const CONFIG_PATH = CONFIG_DIR ++ "config.toml";
const STATE_PATH = CONFIG_DIR ++ "db";

var global_io: std.Io = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    global_io = io;

    const env_map = init.environ_map;
    const home = env_map.get("HOME") orelse "";

    const cwd = std.Io.Dir.cwd();

    const config_path = try std.fs.path.join(gpa, &.{ home, CONFIG_PATH });
    const state_path = try std.fs.path.join(gpa, &.{ home, STATE_PATH });
    defer gpa.free(config_path);
    defer gpa.free(state_path);

    const contents = cwd.readFileAlloc(io, config_path, gpa, .unlimited) catch {
        std.log.err("Could not find config file at path: {s}", .{config_path});

        gpa.free(config_path);
        std.process.exit(1);
    };
    defer gpa.free(contents);

    var conf = config.parse(gpa, contents) catch {
        // TODO: print the error

        gpa.free(contents);
        std.process.exit(1);
    };
    defer conf.deinit();

    var state = try watch.init(gpa, io, state_path);
    defer state.deinit();

    const changed = try state.update(io, conf);
    defer gpa.free(changed);

    try state.store(io, state_path);

    for (changed) |diff| {
        const folder_name = std.fs.path.basename(diff.parent_dir);

        var rel_path = diff.file_path[diff.parent_dir.len..];
        if (rel_path.len > 0 and (rel_path[0] == '/' or rel_path[0] == '\\')) {
            rel_path = rel_path[1..];
        }

        const dest = try std.fs.path.join(gpa, &.{ conf.repo, folder_name, rel_path });
        defer gpa.free(dest);

        if (std.fs.path.dirname(dest)) |dir_path| {
            try cwd.createDirPath(io, dir_path);
        }

        // std.debug.print("Diff item: {s}\n", .{diff.file_path});

        try cwd.copyFile(diff.file_path, cwd, dest, io, .{});
    }

    git.init();
    defer git.deinit();

    const repo = git.repository_open(conf.repo) catch |e| {
        std.log.err("Failed to open repository: {}", .{e});

        std.process.exit(1);
    };
    defer git.repository_deinit(repo);

    const time = std.Io.Clock.real.now(io);
    try git.commit_everything(repo, time);
}

// Probably should do something better
fn log(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = scope;

    const prev = global_io.swapCancelProtection(.blocked);
    defer _ = global_io.swapCancelProtection(prev);

    var buffer: [256]u8 = undefined;

    var stream = std.Io.File.stdout().writerStreaming(global_io, &buffer);
    const stdout = &stream.interface;

    const prefix = "[" ++ @tagName(level) ++ "]";
    stdout.print(prefix ++ format ++ "\n", args) catch return;
    stdout.flush() catch return;
}
