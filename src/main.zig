const std = @import("std");
const zmark = @import("zmark");
const print = std.debug.print;
const Writer = std.io.Writer;

pub fn getDataPath(allocator: std.mem.Allocator) ![]const u8 {
    // std.posix.getenv doesn't allocate — returns a slice into
    // the process environment block, or null
    const home = std.posix.getenv("HOME") orelse return error.HomeNotFound;

    // std.fs.path.join allocates a new string
    return try std.fs.path.join(allocator, &.{ home, ".local", "share", "zmark", "bookmarks.json" });
}

fn printUsage(stdout: *Writer) !void {
    try stdout.writeAll(
        \\zmark, bookmark manager for humans and AI agents
        \\
        \\USAGE:
        \\  zmark <command> [options]
        \\
        \\COMMANDS:
        \\  add <url>     Add a bookmark
        \\  list          List bookmarks
        \\  get <id>      Get a bookmark by ID
        \\  rm <id>       Remove a bookmark
        \\  search <q>    Search bookmarks
        \\  tags          List all tags
        \\  help          Show this help
        \\
        \\FLAGS:
        \\  --title       Bookmark title
        \\  --tags        Comma-separated tags
        \\  --notes       Free-form notes
        \\  --source      Who created it (default: "human")
        \\  --json        Output as JSON
        \\  --limit N     Max results (default: 20)
        \\
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) {
            print("Memory leak detected!\n", .{});
        }
    }
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    // stderr: unbuffered (for errors, always show immediately)
    var stderr_writer = std.fs.File.stderr().writer(&.{});
    const stderr = &stderr_writer.interface;
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const parsedCmd = zmark.cli.parseCommand(args) orelse {
        try printUsage(stdout);
        return;
    };

    switch (parsedCmd.cmd) {
        .add => try handleAdd(allocator, stdout, stderr, parsedCmd.rest),
        .help => try printUsage(stdout),
        else => {
            try stderr.writeAll("Command not implemented yet\n");
        },
    }
}

fn handleAdd(allocator: std.mem.Allocator, stdout: *Writer, stderr: *Writer, args: []const []const u8) !void {
    const title = zmark.cli.parseFlag(args, "--title") orelse {
        try stderr.writeAll("title is required. use zmark add --title <title>\n");
        return;
    };
    const url = zmark.cli.parseFlag(args, "--url") orelse {
        try stderr.writeAll("url is required. use zmark add --url <url>\n");
        return;
    };
    const tags_str = zmark.cli.parseFlag(args, "--tags");
    const notes = zmark.cli.parseFlag(args, "--notes");
    const source_str = zmark.cli.parseFlag(args, "--source");
    const source = zmark.BookmarkSource.fromString(source_str) orelse .human;

    // Parse tags here, before init
    var parsedTags: []const []const u8 = &[_][]const u8{};
    if (tags_str) |t| {
        parsedTags = try zmark.splitTags(allocator, t);
    }
    defer allocator.free(parsedTags);

    const id_buf = zmark.generateUlid();
    const bookmark = zmark.Bookmark.init(&id_buf, url, title, parsedTags, notes, source);

    const dataPath = try getDataPath(allocator);
    defer allocator.free(dataPath);

    var store = try zmark.Store.init(allocator, dataPath);
    defer store.deinit();

    try store.add(bookmark);
    try store.save();

    try stdout.print("Bookmark added: {s}\n", .{bookmark.url});
}
