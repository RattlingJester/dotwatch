const std = @import("std");
const builtin = @import("builtin");

const git = @import("git_wrapper.zig");
const watcher = @import("file_watcher.zig");
const Config = @import("config.zig");

pub const std_options = std.Options{ .logFn = log, .log_level = .info };

const CONFIG_DIR = switch (builtin.target.os.tag) {
    .windows => "./", // Use program folder for windows
    .linux => ".config/dotwatch/",
    else => @compileError("OS not supported"),
};
const CONFIG_PATH = CONFIG_DIR ++ "config.zon";
const STATE_PATH = CONFIG_DIR ++ "db";

var global_io: std.Io = undefined;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var buffer: [4096]u8 = undefined;
    var buffer_alloc = std.heap.BufferFirstAllocator.init(&buffer, gpa);
    const alloc = buffer_alloc.allocator();

    global_io = io;

    const env_map = init.environ_map;
    const home = env_map.get("HOME") orelse "";

    const cwd = std.Io.Dir.cwd();

    const config_path = try std.fs.path.join(alloc, &.{ home, CONFIG_PATH });
    const state_path = try std.fs.path.join(alloc, &.{ home, STATE_PATH });
    defer alloc.free(config_path);
    defer alloc.free(state_path);

    const contents = cwd.readFileAllocOptions(io, config_path, alloc, .unlimited, .@"8", 0) catch {
        std.log.err("Could not find config file at path: {s}", .{config_path});

        std.process.exit(1);
    };
    defer alloc.free(contents);

    var conf = Config.parse(alloc, arena, contents) catch |err| {
        std.log.err("Config parse error: {}", .{err});

        std.process.exit(1);
    };

    var state = try watcher.init(alloc, io, state_path);
    defer state.deinit();

    const diff = try state.update(io, &conf);
    defer alloc.free(diff);

    if (diff.len == 0) return; // Nothing to do here

    // try copy_files(io, alloc, diff, &conf);
    // try state.store(io, state_path);

    // git.init();
    // defer git.deinit();

    // const repo = git.repository_open(conf.repo) catch |e| {
    //     std.log.err("Failed to open repository: {}", .{e});

    //     std.process.exit(1);
    // };
    // defer git.repository_deinit(repo);

    // const time = std.Io.Clock.real.now(io);
    // try git.commit_everything(repo, time);
}

fn copy_files(
    io: std.Io,
    alloc: std.mem.Allocator,
    changed: []const watcher.Diff,
    config: *const Config,
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
