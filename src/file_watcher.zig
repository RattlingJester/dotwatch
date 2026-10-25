const std = @import("std");
const Config = @import("config.zig");
// const Tracked = Config.Tracked;
const log = std.log.scoped(.state);

const Self = @This();
const StateMap = std.StringHashMap(i128);

pub const Diff = struct {
    file_path: []const u8,
    parent_dir: []const u8,
};

// TODO: remove globals
var n_new: usize = 0;
var n_modified: usize = 0;
var n_unchanged: usize = 0;

map: StateMap,
diff: std.ArrayList(Diff) = .empty,
alloc: std.mem.Allocator,

pub fn init(
    alloc: std.mem.Allocator,
    io: std.Io,
    db_path: []const u8,
) !Self {
    const map = load(alloc, io, db_path) catch |err| switch (err) {
        error.FileNotFound => blk: {
            log.warn("state file '{s}' not found, starting with empty state", .{db_path});
            break :blk StateMap.init(alloc);
        },
        else => {
            log.err("failed to load state file '{s}': {s}", .{ db_path, @errorName(err) });

            return err;
        },
    };

    log.info("loaded {d} tracked entries from '{s}'", .{ map.count(), db_path });

    return .{ .alloc = alloc, .map = map };
}

pub fn deinit(self: *Self) void {
    free_keys(self.alloc, &self.map);
    self.map.deinit();
}

pub fn update(
    self: *Self,
    io: std.Io,
    config: *const Config,
) ![]const Diff {
    const alloc = self.alloc;

    errdefer self.diff.deinit(alloc);

    for (config.tracked) |entry| {
        log.info("scanning '{s}'", .{entry});

        const stat = std.Io.Dir.cwd().statFile(io, entry, .{}) catch |err| {
            log.err("cannot stat '{s}': {}", .{ entry, err });

            return err;
        };

        switch (stat.kind) {
            .directory => {
                var dir = std.Io.Dir.cwd().openDir(io, entry, .{
                    .iterate = true,
                    .follow_symlinks = false,
                }) catch |err| {
                    log.err("cannot open tracked directory '{s}': {}", .{ entry, err });

                    return err;
                };
                defer dir.close(io);

                try self.process_dir(entry, dir, config.ignore, alloc, io);
            },
            .file => try self.process_file(entry, "", stat, alloc),
            else => return error.NotSupportedFileType,
        }
    }

    log.info(
        "scan complete: {d} new, {d} modified, {d} unchanged",
        .{ n_new, n_modified, n_unchanged },
    );

    return self.diff.toOwnedSlice(alloc);
}

pub fn store(self: *const Self, io: std.Io, path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const byte_size = size_of_map(&self.map);

    const file = try cwd.createFile(io, path, .{});
    defer file.close(io);

    const write_buf = try self.alloc.alloc(u8, byte_size);
    defer self.alloc.free(write_buf);

    var file_writer = file.writer(io, write_buf);
    const w = &file_writer.interface;

    try w.writeInt(u32, @intCast(self.map.count()), .little);

    var it = self.map.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        try w.writeInt(u32, @intCast(key.len), .little);
        try w.writeAll(key);
        try w.writeInt(i128, entry.value_ptr.*, .little);
    }

    try w.flush();

    log.info("saved {d} entries to '{s}'", .{ self.map.count(), path });
}

fn load(alloc: std.mem.Allocator, io: std.Io, db_path: []const u8) !StateMap {
    const file = try std.Io.Dir.cwd().openFile(io, db_path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    const size = stat.size;

    const read_buf = try alloc.alloc(u8, size);
    defer alloc.free(read_buf);

    var file_reader = file.reader(io, read_buf);
    const r = &file_reader.interface;

    var map = StateMap.init(alloc);
    errdefer {
        free_keys(alloc, &map);
        map.deinit();
    }

    const num_entries = try r.takeInt(u32, .little);
    try map.ensureTotalCapacity(num_entries);

    for (0..num_entries) |_| {
        const key_len = try r.takeInt(u32, .little);

        const key = try alloc.alloc(u8, key_len);
        errdefer alloc.free(key);

        try r.readSliceAll(key);
        const value = try r.takeInt(i128, .little);

        const gop = map.getOrPutAssumeCapacity(key);
        if (gop.found_existing) {
            log.warn("duplicate key '{s}' in state file, keeping the latest value", .{key});
            alloc.free(key);
        }
        gop.value_ptr.* = value;
    }

    return map;
}

fn process_dir(
    self: *Self,
    entry: [:0]const u8,
    dir: std.Io.Dir,
    ignore: []const []const u8,
    alloc: std.mem.Allocator,
    io: std.Io,
) !void {
    var walker = try dir.walk(alloc);
    defer walker.deinit();

    // Walker visits subdirectories automatically
    while (try walker.next(io)) |item| {
        if (item.kind == .file) {
            if (should_ignore(item.path, ignore)) continue;

            const stat = dir.statFile(io, item.path, .{}) catch |err| {
                log.err("cannot stat '{s}/{s}': {}", .{ entry, item.path, err });

                return err;
            };

            try self.process_file(entry, item.path, stat, alloc);
        } else continue;
    }
}
fn process_file(
    self: *Self,
    entry: [:0]const u8,
    sub_path: []const u8,
    stat: std.Io.Dir.Stat,
    alloc: std.mem.Allocator,
) !void {
    const mtime: i128 = stat.mtime.nanoseconds;

    const full = try std.fs.path.join(alloc, &.{ entry, sub_path });

    if (self.map.getEntry(full)) |kv| {
        alloc.free(full);

        if (kv.value_ptr.* != mtime) {
            kv.value_ptr.* = mtime;

            try self.diff.append(alloc, .{
                .file_path = kv.key_ptr.*,
                .parent_dir = entry,
            });
            n_modified += 1;

            log.info("modified: {s}", .{kv.key_ptr.*});
        } else {
            n_unchanged += 1;
            log.debug("unchanged: {s}", .{kv.key_ptr.*});
        }
    } else {
        errdefer alloc.free(full);

        try self.map.put(full, mtime);

        try self.diff.append(alloc, .{
            .file_path = full,
            .parent_dir = entry,
        });
        n_new += 1;

        log.info("new: {s}", .{full});
    }
}

fn free_keys(alloc: std.mem.Allocator, map: *StateMap) void {
    var it = map.keyIterator();
    while (it.next()) |key| alloc.free(key.*);
}

fn should_ignore(path: []const u8, ignore_patterns: []const []const u8) bool {
    const ext = std.fs.path.extension(path);
    const basename = std.fs.path.basename(path);

    for (ignore_patterns) |pattern| {
        if (std.mem.startsWith(u8, pattern, "*.")) {
            if (std.mem.eql(u8, ext, pattern[1..])) return true;
        } else {
            if (std.mem.eql(u8, basename, pattern)) return true;
        }
    }

    return false;
}

/// Get allocation size for my binary format
fn size_of_map(map: *const StateMap) usize {
    var size: usize = @sizeOf(u32);

    var it = map.iterator();
    while (it.next()) |entry| {
        size += @sizeOf(u32);
        size += entry.key_ptr.*.len;
        size += @sizeOf(i128);
    }

    return size;
}
