const std = @import("std");
const g = @import("git2.zig");

pub fn init() void {
    _ = g.git_libgit2_init();
}

pub fn deinit() void {
    _ = g.git_libgit2_shutdown();
}

pub fn repository_open(path: [:0]const u8) ?*g.git_repository {
    var repo: ?*g.git_repository = null;
    const err = g.git_repository_open(&repo, path.ptr);

    if (err == 0) {
        return repo;
    } else return null;
}

pub fn repository_deinit(repo: *g.git_repository) void {
    g.git_repository_free(repo);
}

pub fn revparse_single(repo: ?*g.git_repository, spec: [:0]const u8) ?*g.git_object {
    var obj: ?*g.git_object = null;
    const err = g.git_revparse_single(&obj, repo, spec.ptr);

    if (err == 0) {
        return obj;
    } else return null;
}

pub fn object_deinit(obj: *g.git_object) void {
    g.git_object_free(obj);
}

// TODO
pub fn commit_everything(repo: *g.git_repository, time: std.Io.Timestamp) !void {
    _ = repo; // autofix
    _ = time; // autofix
}
