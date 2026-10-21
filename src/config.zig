const std = @import("std");

const Self = @This();

const INIT_CAP = 1024;

const Tracked = struct {
    value: []const u8,
    offset: usize,
};

tracked: std.ArrayList(Tracked) = .empty,
repo: []const u8 = "",

pub fn parse(alloc: std.mem.Allocator, buffer: []const u8) !Self {
    var config = Self{};
    errdefer config.deinit(alloc);

    var tokens = std.mem.tokenizeAny(u8, buffer, "\n\r");
    var is_in_tracked_array = false;

    while (tokens.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t");

        if (line.len == 0 or line[0] == '#') continue;

        if (is_in_tracked_array) {
            if (std.mem.indexOfScalar(u8, line, ']')) |bracket_idx| {
                const pre_bracket = std.mem.trim(u8, line[0..bracket_idx], " \t,");

                if (pre_bracket.len > 0) {
                    try append(alloc, &config.tracked, buffer, pre_bracket);
                }

                is_in_tracked_array = false;

                continue;
            }

            const clean_item = std.mem.trim(u8, line, " \t,");
            try append(alloc, &config.tracked, buffer, clean_item);

            continue;
        }

        if (std.mem.indexOfScalar(u8, line, '=')) |eq_idx| {
            const key = std.mem.trim(u8, line[0..eq_idx], " \t");
            const val = std.mem.trim(u8, line[eq_idx + 1 ..], " \t");

            if (std.mem.eql(u8, key, "repo")) {
                config.repo = try alloc.dupe(u8, std.mem.trim(u8, val, "\"\'"));
            } else if (std.mem.eql(u8, key, "tracked")) {
                if (std.mem.indexOfScalar(u8, val, '[')) |bracket_idx| {
                    is_in_tracked_array = true;

                    const remainder = std.mem.trim(u8, val[bracket_idx + 1 ..], " \t,");
                    if (remainder.len > 0) {
                        if (std.mem.indexOfScalar(u8, remainder, ']')) |end_bracket| {
                            const inline_item = std.mem.trim(u8, remainder[0..end_bracket], " \t,");

                            try append(alloc, &config.tracked, buffer, inline_item);
                            is_in_tracked_array = false;
                        } else {
                            try append(alloc, &config.tracked, buffer, remainder);
                        }
                    }
                }
            }
        }
    }

    return config;
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    for (self.tracked.items) |item| {
        alloc.free(item.value);
    }
    self.tracked.deinit(alloc);

    if (self.repo.len > 0) {
        alloc.free(self.repo);
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

    const owned_value = try alloc.dupe(u8, clean_value);
    errdefer alloc.free(owned_value);

    try list.append(alloc, Tracked{
        .value = owned_value,
        .offset = start_offset,
    });
}
