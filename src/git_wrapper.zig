const std = @import("std");
const g = @import("git2.zig");

pub const GitError = error{
    GenericError, // GIT_ERROR = -1
    NotFound, // GIT_ENOTFOUND = -3
    Exists, // GIT_EEXISTS = -4
    Ambiguous, // GIT_EAMBIGUOUS = -5
    BufferTooShort, // GIT_EBUFS = -6
    UserCallbackAborted, // GIT_EUSER = -7
    BareRepository, // GIT_EBAREREPO = -8
    UnbornBranch, // GIT_EUNBORNBRANCH = -9
    UnmergedEntries, // GIT_EUNMERGED = -10
    NonFastForward, // GIT_ENONFASTFORWARD = -11
    InvalidSpec, // GIT_EINVALIDSPEC = -12
    Conflict, // GIT_ECONFLICT = -13
    Locked, // GIT_ELOCKED = -14
    Modified, // GIT_EMODIFIED = -15
    AuthRequired, // GIT_EAUTH = -16
    CertificateError, // GIT_ECERTIFICATE = -17
    Applied, // GIT_EAPPLIED = -18
    PeelError, // GIT_EPEEL = -19
    EOF, // GIT_EEOF = -20
    InvalidOperation, // GIT_EINVALID = -21
    UncommittedChanges, // GIT_EUNCOMMITTED = -22
    DirectoryError, // GIT_EDIRECTORY = -23
    MergeConflict, // GIT_EMERGECONFLICT = -24
    Passthrough, // GIT_PASSTHROUGH = -30
    IterOver, // GIT_ITEROVER = -31
    Retry, // GIT_RETRY = -32
    Mismatch, // GIT_EMISMATCH = -33
    IndexDirty, // GIT_EINDEXDIRTY = -34
    ApplyFail, // GIT_EAPPLYFAIL = -35
    UnknownLibGit2Error,
};

pub const GitErrorMessage = struct {
    message: []const u8,
    class: c_int,
};

pub fn init() void {
    _ = g.git_libgit2_init();
}

pub fn deinit() void {
    _ = g.git_libgit2_shutdown();
}

pub fn repository_open(path: [:0]const u8) GitError!*g.git_repository {
    var repo: ?*g.git_repository = null;
    const err = g.git_repository_open(&repo, path.ptr);
    try handle_err(err);

    return repo.?;
}

pub fn repository_deinit(repo: *g.git_repository) void {
    g.git_repository_free(repo);
}

pub fn revparse_single(repo: ?*g.git_repository, spec: [:0]const u8) GitError!*g.git_object {
    var obj: ?*g.git_object = null;
    const err = g.git_revparse_single(&obj, repo, spec.ptr);
    try handle_err(err);

    return obj.?;
}

pub fn object_deinit(obj: *g.git_object) void {
    g.git_object_free(obj);
}

pub fn repository_index(repo: *g.git_repository) GitError!*g.git_index {
    var index: ?*g.git_index = null;
    try handle_err(g.git_repository_index(&index, repo));

    return index.?;
}

pub fn index_deinit(index: *g.git_index) void {
    g.git_index_free(index);
}

pub fn index_add_all(index: *g.git_index) GitError!void {
    try handle_err(g.git_index_add_all(index, null, g.GIT_INDEX_ADD_DEFAULT, null, null));
}

pub fn index_write(index: *g.git_index) GitError!void {
    try handle_err(g.git_index_write(index));
}

pub fn index_write_tree(index: *g.git_index, repo: *g.git_repository) GitError!*g.git_tree {
    var tree_id: g.git_oid = undefined;
    try handle_err(g.git_index_write_tree(&tree_id, index));

    var tree: ?*g.git_tree = null;
    try handle_err(g.git_tree_lookup(&tree, repo, &tree_id));

    return tree.?;
}

pub fn tree_free(tree: *g.git_tree) void {
    g.git_tree_free(tree);
}

pub fn signature_default(repo: *g.git_repository) GitError!*g.git_signature {
    var sig: ?*g.git_signature = null;
    try handle_err(g.git_signature_default(&sig, repo));

    return sig.?;
}

pub fn signature_deinit(sig: *g.git_signature) void {
    g.git_signature_free(sig);
}

pub fn commit_free(commit: *g.git_commit) void {
    g.git_commit_free(commit);
}

pub fn commit_everything(repo: *g.git_repository, time: std.Io.Timestamp) !void {
    const epoch_seconds = std.time.epoch.EpochSeconds{
        .secs = @intCast(time.toSeconds()),
    };

    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    var buf: [128]u8 = undefined;
    const message = try std.fmt.bufPrintSentinel(&buf, "{d:0>2}-{d:0>2}-{d:0>4}", .{
        month_day.day_index + 1,
        month_day.month.numeric(),
        year_day.year,
    }, 0);

    const index = try repository_index(repo);
    defer index_deinit(index);

    try index_add_all(index);
    try index_write(index);

    const tree = try index_write_tree(index, repo);
    defer tree_free(tree);

    const sig = try signature_default(repo);
    defer signature_deinit(sig);

    var parent_commit: ?*g.git_commit = null;
    defer if (parent_commit) |p| commit_free(p);

    var parent_id: g.git_oid = undefined;
    var parent_count: u32 = 1;

    if (g.git_reference_name_to_id(&parent_id, repo, "HEAD") == 0) {
        var p: ?*g.git_commit = null;
        try handle_err(g.git_commit_lookup(&p, repo, &parent_id));

        parent_commit = p;
    } else {
        parent_count = 0;
    }

    var commit_id: g.git_oid = undefined;
    var parents = [_]?*g.git_commit{parent_commit};

    try handle_err(g.git_commit_create(
        &commit_id,
        repo,
        "HEAD",
        sig,
        sig,
        null,
        message,
        tree,
        parent_count,
        @ptrCast(&parents),
    ));
}

pub fn handle_err(code: c_int) GitError!void {
    if (code >= 0) return;

    switch (code) {
        g.GIT_ERROR => return GitError.GenericError,
        g.GIT_ENOTFOUND => return GitError.NotFound,
        g.GIT_EEXISTS => return GitError.Exists,
        g.GIT_EAMBIGUOUS => return GitError.Ambiguous,
        g.GIT_EBUFS => return GitError.BufferTooShort,
        g.GIT_EUSER => return GitError.UserCallbackAborted,
        g.GIT_EBAREREPO => return GitError.BareRepository,
        g.GIT_EUNBORNBRANCH => return GitError.UnbornBranch,
        g.GIT_EUNMERGED => return GitError.UnmergedEntries,
        g.GIT_ENONFASTFORWARD => return GitError.NonFastForward,
        g.GIT_EINVALIDSPEC => return GitError.InvalidSpec,
        g.GIT_ECONFLICT => return GitError.Conflict,
        g.GIT_ELOCKED => return GitError.Locked,
        g.GIT_EMODIFIED => return GitError.Modified,
        g.GIT_EAUTH => return GitError.AuthRequired,
        g.GIT_ECERTIFICATE => return GitError.CertificateError,
        g.GIT_EAPPLIED => return GitError.Applied,
        g.GIT_EPEEL => return GitError.PeelError,
        g.GIT_EEOF => return GitError.EOF,
        g.GIT_EINVALID => return GitError.InvalidOperation,
        g.GIT_EUNCOMMITTED => return GitError.UncommittedChanges,
        g.GIT_EDIRECTORY => return GitError.DirectoryError,
        g.GIT_EMERGECONFLICT => return GitError.MergeConflict,
        g.GIT_PASSTHROUGH => return GitError.Passthrough,
        g.GIT_ITEROVER => return GitError.IterOver,
        g.GIT_RETRY => return GitError.Retry,
        g.GIT_EMISMATCH => return GitError.Mismatch,
        g.GIT_EINDEXDIRTY => return GitError.IndexDirty,
        g.GIT_EAPPLYFAIL => return GitError.ApplyFail,
        else => return GitError.UnknownLibGit2Error,
    }
}

pub fn last_error() ?GitErrorMessage {
    const err_ptr = g.git_error_last();
    if (err_ptr == null) return null;

    return GitErrorMessage{
        .message = std.mem.span(err_ptr.*.message),
        .class = err_ptr.*.klass,
    };
}
