const std = @import("std");

const config = @import("config.zig");

const Error = error{
    MissingConfigPath,
    TooManyArguments,
};

const Options = enum {
    none,
    verbose,
};

const Args = struct {
    config_path: []const u8,
    options: Options,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_file_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_file_writer.interface;

    var arg_iter = try init.minimal.args.iterateAllocator(arena);
    defer arg_iter.deinit();

    const args = parse_args(&arg_iter) catch |e| {
        std.log.err("Incorrect argument: {}", .{e});
        try print_help(stdout);

        std.process.exit(1);
    };

    const file = try std.Io.Dir.cwd().readFileAlloc(io, args.config_path, gpa, .unlimited);
    defer gpa.free(file);

    std.debug.print("Config path: {s}\n", .{args.config_path});
    std.debug.print("Options: {}\n", .{args.options});
    std.debug.print("\nConfig file:\n{s}\n", .{file});

    const conf = try config.parse(file);
    _ = conf; // autofix

}

pub fn parse_args(
    iter: *std.process.Args.Iterator,
) Error!Args {
    _ = iter.skip();

    var config_path: ?[]const u8 = null;
    var options: Options = .none;

    while (iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options = .verbose;
        } else {
            if (config_path == null) {
                config_path = arg;
            } else {
                return Error.TooManyArguments;
            }
        }
    }

    return Args{
        .config_path = config_path orelse return Error.MissingConfigPath,
        .options = options,
    };
}

fn print_help(writer: *std.Io.Writer) !void {
    try writer.print(
        \\dotwatch — A configuration watch tool
        \\
        \\Usage:
        \\  dotwatch [options] <config_path>
        \\
        \\Arguments:
        \\  <config_path>    Path to the configuration file (Required)
        \\
        \\Options:
        \\  -v, --verbose    Enable verbose debug logging
        \\  -h, --help       Display this help message
        \\
    , .{});

    try writer.flush();
}
