const std = @import("std");
const print = std.debug.print;

/// All supported commands.
pub const Command = enum {
    add,
    list,
    get,
    rm,
    search,
    tags,
    help,

    pub fn fromString(str: []const u8) ?Command {
        const fields = @typeInfo(Command).@"enum".fields;
        inline for (fields) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};

/// Parsed command-line options for the `add` command.
pub const AddOptions = struct {
    url: []const u8,
    title: []const u8 = "",
    tags: []const u8 = "", // comma-separated, we split later
    notes: []const u8 = "",
    source: []const u8 = "human",
};

/// Parsed command-line options for commands that filter.
pub const FilterOptions = struct {
    query: []const u8 = "",
    tag: []const u8 = "",
    source: []const u8 = "",
    limit: usize = 20,
    json_output: bool = false,
};

/// Parse args into a command + remaining args.
/// Returns null if no valid command found.
pub fn parseCommand(args: []const []const u8) ?struct { cmd: Command, rest: []const []const u8 } {
    // args[0] is the binary name ("zmark"), args[1] is the command
    if (args.len < 2) return null;

    const cmd = Command.fromString(args[1]) orelse return null;
    return .{
        .cmd = cmd,
        .rest = if (args.len > 2) args[2..] else &[_][]const u8{},
    };
}

/// Parse a flag value from args. E.g. parseFlag(args, "--title") returns "My Title"
/// from: --title "My Title"
pub fn parseFlag(args: []const []const u8, flag: []const u8) ?[]const u8 {
    for (args, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, flag)) {
            if (i + 1 < args.len) return args[i + 1];
        }
    }
    return null;
}
