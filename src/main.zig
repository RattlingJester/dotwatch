const std = @import("std");
const builtin = @import("builtin");

const watcher = @import("file_watcher.zig");
const Config = @import("config.zig");
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

        std.process.exit(1);
    };
    defer gpa.free(contents);

    var conf = Config.parse(gpa, contents) catch |err| {
        std.log.err("Config parse error: {}", .{err});

        std.process.exit(1);
    };
    defer conf.deinit(gpa);

    var state = try watcher.init(gpa, io, state_path);
    defer state.deinit();

    const changed = try state.update(io, &conf);
    defer gpa.free(changed);

    try copy_files(io, gpa, changed, conf);

    try state.store(io, state_path);

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

fn copy_files(
    io: std.Io,
    alloc: std.mem.Allocator,
    changed: []const watcher.Diff,
    config: Config,
) !void {
    const cwd = std.Io.Dir.cwd();

    for (changed) |diff| {
        const folder_name = std.fs.path.basename(diff.parent_dir);

        var rel_path = diff.file_path[diff.parent_dir.len..];
        if (rel_path.len > 0 and (rel_path[0] == '/' or rel_path[0] == '\\')) {
            rel_path = rel_path[1..];
        }

        const dest = try std.fs.path.join(alloc, &.{ config.repo, folder_name, rel_path });
        defer alloc.free(dest);

        if (std.fs.path.dirname(dest)) |dir_path| {
            try cwd.createDirPath(io, dir_path);
        }

        try cwd.copyFile(diff.file_path, cwd, dest, io, .{});
    }
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
