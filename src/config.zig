const std = @import("std");

const Self = @This();

pub const Tracked = struct {
    tracked_path: [:0]const u8,
    offset: usize,
};

tracked: std.ArrayList(Tracked) = .empty,
ignore_files: std.ArrayList([]const u8) = .empty,
repo: [:0]const u8 = undefined,

pub fn parse(alloc: std.mem.Allocator, buffer: []const u8) !Self {
    var config = Self{};
    errdefer config.deinit(alloc);

    var tokens = std.mem.tokenizeAny(u8, buffer, "\n\r");
    var current_section: enum { none, tracked, ignore_files } = .none;

    var found_repo = false;
    var found_tracked = false;
    var found_config_section = false;

    while (tokens.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t");
        if (line.len == 0 or line[0] == '#') continue;

        if (current_section == .tracked) {
            found_tracked = true;
            if (std.mem.indexOfScalar(u8, line, ']')) |bracket_idx| {
                const item = std.mem.trim(u8, line[0..bracket_idx], " \t,");
                if (item.len > 0) try append(alloc, &config.tracked, buffer, item);
                current_section = .none;
            } else {
                const item = std.mem.trim(u8, line, " \t,");
                if (item.len > 0) try append(alloc, &config.tracked, buffer, item);
            }
            continue;
        }

        if (current_section == .ignore_files) {
            if (std.mem.indexOfScalar(u8, line, ']')) |bracket_idx| {
                const item = std.mem.trim(u8, line[0..bracket_idx], " \t,\"'");
                if (item.len > 0) {
                    const owned = try alloc.dupe(u8, item);
                    try config.ignore_files.append(alloc, owned);
                }
                current_section = .none;
            } else {
                const item = std.mem.trim(u8, line, " \t,\"'");
                if (item.len > 0) {
                    const owned = try alloc.dupe(u8, item);
                    try config.ignore_files.append(alloc, owned);
                }
            }
            continue;
        }

        if (std.mem.eql(u8, line, "[config]")) {
            found_config_section = true;
            continue;
        }

        if (std.mem.indexOfScalar(u8, line, '=')) |eq_idx| {
            const key = std.mem.trim(u8, line[0..eq_idx], " \t");
            const val = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");

            if (std.mem.eql(u8, key, "repo")) {
                const path = std.mem.trim(u8, val, "\"'");
                config.repo = try alloc.dupeSentinel(u8, path, 0);
                found_repo = true;
            } else if (std.mem.eql(u8, key, "tracked")) {
                found_tracked = true;
                try parse_inline_or_arr(alloc, &config.tracked, buffer, val, &current_section, .tracked);
            } else if (std.mem.eql(u8, key, "ignore_files")) {
                var dummy_list = std.ArrayList([]const u8).empty;
                defer {
                    for (dummy_list.items) |item| alloc.free(item);
                    dummy_list.deinit(alloc);
                }

                var state: enum { none, tracked, ignore_files } = .none;
                try parse_inline_or_arr(alloc, &dummy_list, buffer, val, &state, .ignore_files);

                for (dummy_list.items) |item| {
                    const clean_item = std.mem.trim(u8, item, "\"'");
                    const owned = try alloc.dupe(u8, clean_item);
                    try config.ignore_files.append(alloc, owned);
                }
                if (state == .ignore_files) current_section = .ignore_files;
            }
        }
    }

    if (!found_repo) return error.MissingRequiredRepo;
    if (!found_tracked or config.tracked.items.len == 0) return error.MissingRequiredTracked;
    if (!found_config_section) return error.MissingRequiredConfigSection;

    return config;
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    for (self.tracked.items) |item| {
        allocator.free(item.tracked_path);
    }
    self.tracked.deinit(allocator);

    for (self.ignore_files.items) |item| {
        allocator.free(item);
    }
    self.ignore_files.deinit(allocator);

    if (self.repo.len > 0) {
        allocator.free(self.repo);
    }
}

fn append(
    alloc: std.mem.Allocator,
    list: *std.ArrayList(Tracked),
    base_buffer: []const u8,
    raw_slice: []const u8,
) !void {
    const clean_value = std.mem.trim(u8, raw_slice, "\"\'");
    if (clean_value.len == 0) return;

    const start_offset = @intFromPtr(clean_value.ptr) - @intFromPtr(base_buffer.ptr);

    const owned_value = try alloc.dupeSentinel(u8, clean_value, 0);
    errdefer alloc.free(owned_value);

    try list.append(alloc, Tracked{
        .tracked_path = owned_value,
        .offset = start_offset,
    });
}

fn parse_inline_or_arr(
    alloc: std.mem.Allocator,
    list: anytype,
    buffer: []const u8,
    val: []const u8,
    current_section: anytype,
    section_type: @TypeOf(current_section.*),
) !void {
    const bracket_idx = std.mem.indexOfScalar(u8, val, '[') orelse return;
    const remainder = std.mem.trim(u8, val[bracket_idx + 1 ..], " \t,");
    if (remainder.len == 0) {
        current_section.* = section_type;
        return;
    }

    if (std.mem.indexOfScalar(u8, remainder, ']')) |end_bracket| {
        const inline_item = std.mem.trim(u8, remainder[0..end_bracket], " \t,");
        if (inline_item.len > 0) {
            if (@TypeOf(list.*) == std.ArrayList(Tracked)) {
                try append(alloc, list, buffer, inline_item);
            } else {
                const owned = try alloc.dupe(u8, inline_item);
                try list.append(alloc, owned);
            }
        }
    } else {
        if (@TypeOf(list.*) == std.ArrayList(Tracked)) {
            try append(alloc, list, buffer, remainder);
        } else {
            const owned = try alloc.dupe(u8, remainder);
            try list.append(alloc, owned);
        }
        current_section.* = section_type;
    }
}
