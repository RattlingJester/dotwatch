const Self = @This();

pub const ParseEror = error{};

pub fn parse(contents: []const u8) ParseEror!Self {
    _ = contents; // autofix

    return .{};
}
