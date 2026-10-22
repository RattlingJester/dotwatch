const std = @import("std");
const builtint = @import("builtin");

const config = @import("config.zig");
const git = @import("git_wrapper.zig");

const CONFIG_DIR = ".config/dotwatch/";
const CONFIG_PATH = CONFIG_DIR ++ "config.toml";
const STATE_PATH = CONFIG_DIR ++ "db";

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const env_map = init.environ_map;
    const home = env_map.get("HOME") orelse return error.HomeNotFound;

    const path = try std.fs.path.join(gpa, &.{ home, CONFIG_PATH });
    const file = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited) catch {
        std.log.err("Could not find config file at path: {s}", .{path});

        gpa.free(path);
        std.process.exit(1);
    };

    gpa.free(path); // Path not needed anymore

    var conf = config.parse(gpa, file) catch {
        // TODO: print the error

        gpa.free(file);
        std.process.exit(1);
    };
    defer conf.deinit(gpa);

    gpa.free(file); // Whole file not needed anymore

    std.debug.print("Repo: {s}\n", .{conf.repo});
    for (conf.tracked.items) |item| {
        std.debug.print("Tracked (Offset {d}): {s}\n", .{ item.offset, item.value });
    }

    git.init();
    defer git.deinit();

    const repo = git.repository_open(conf.repo) orelse {
        std.log.err("Failed to open repository", .{});

        std.process.exit(1);
    };
    defer git.repository_deinit(repo);

    const head = git.revparse_single(repo, "HEAD^{commit}") orelse {
        std.log.err("Error getting HEAD lol", .{});

        std.process.exit(1);
    };
    defer git.object_deinit(head);

    const commit: ?*git.g.git_commit = @ptrCast(head);

    std.debug.print("Commit message: {s}\n", .{git.g.git_commit_message(commit)});
}
