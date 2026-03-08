const std = @import("std");
const zmark = @import("zmark");
const build_options = @import("build_options");
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
        \\  add           Add a bookmark
        \\  list          List bookmarks
        \\  get           Get a bookmark by ID
        \\  rm            Remove a bookmark
        \\  search        Search bookmarks
        \\  version       Print version
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

fn printAddUsage(stdout: *Writer) !void {
    try stdout.writeAll(
        \\USAGE:
        \\  zmark add --url <url> --title <title> [options]
        \\
        \\  Add a new bookmark.
        \\
        \\REQUIRED:
        \\  --url <url>       URL to bookmark
        \\  --title <title>   Title for the bookmark
        \\
        \\OPTIONS:
        \\  --tags <tags>     Comma-separated tags (e.g. "zig,tools")
        \\  --notes <text>    Free-form notes
        \\  --source <src>    Who created it (default: "human")
        \\
    );
}

fn printListUsage(stdout: *Writer) !void {
    try stdout.writeAll(
        \\USAGE:
        \\  zmark list
        \\
        \\  List all saved bookmarks.
        \\
    );
}

fn printGetUsage(stdout: *Writer) !void {
    try stdout.writeAll(
        \\USAGE:
        \\  zmark get --id <id>
        \\
        \\  Get a single bookmark by its ID.
        \\
        \\REQUIRED:
        \\  --id <id>   Bookmark ID (ULID)
        \\
    );
}

fn printRemoveUsage(stdout: *Writer) !void {
    try stdout.writeAll(
        \\USAGE:
        \\  zmark rm --id <id>
        \\
        \\  Remove a bookmark by its ID.
        \\
        \\REQUIRED:
        \\  --id <id>   Bookmark ID (ULID)
        \\
    );
}

fn printSearchUsage(stdout: *Writer) !void {
    try stdout.writeAll(
        \\USAGE:
        \\  zmark search [--query <text>] [--tags <tags>]
        \\
        \\  Search bookmarks. At least one option is required.
        \\
        \\OPTIONS:
        \\  --query <text>   Full-text search against title, URL, and notes
        \\  --tags <tags>    Filter by tags (comma-separated)
        \\
    );
}

fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
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
        .version => try stdout.print("zmark {s}\n", .{build_options.version}),
        .help => try printUsage(stdout),
        .search => try handleSearch(allocator, stdout, stderr, parsedCmd.rest),
        .list => try handleList(allocator, stdout, stderr, parsedCmd.rest),
        .get => try handleGet(allocator, stdout, stderr, parsedCmd.rest),
        .rm => try handleRemove(allocator, stdout, stderr, parsedCmd.rest),
        else => {
            try stderr.writeAll("Command not implemented yet\n");
        },
    }
}

pub fn printBookmark(stdout: *std.Io.Writer, bm: *zmark.Bookmark, index: usize) !void {
    try stdout.print("  {d}. {s}\n", .{ index + 1, bm.title });
    try stdout.print("     ID: {s}\n", .{bm.id});
    try stdout.print("     {s}\n", .{bm.url});
    if (bm.tags.len > 0) {
        try stdout.writeAll("     ");
        for (bm.tags, 0..) |tag, i| {
            if (i > 0) try stdout.writeAll(", ");
            try stdout.print("#{s}", .{tag});
        }
        try stdout.writeAll("\n");
    }
    try stdout.writeAll("\n");
}

fn handleAdd(allocator: std.mem.Allocator, stdout: *Writer, stderr: *Writer, args: []const []const u8) !void {
    if (hasFlag(args, "--help")) {
        try printAddUsage(stdout);
        return;
    }
    const title = zmark.cli.parseFlag(args, "--title") orelse {
        try stderr.writeAll("error: --title is required\n\n");
        try printAddUsage(stderr);
        return;
    };
    const url = zmark.cli.parseFlag(args, "--url") orelse {
        try stderr.writeAll("error: --url is required\n\n");
        try printAddUsage(stderr);
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

fn handleSearch(allocator: std.mem.Allocator, stdout: *Writer, stderr: *Writer, args: []const []const u8) !void {
    if (hasFlag(args, "--help")) {
        try printSearchUsage(stdout);
        return;
    }
    const query = zmark.cli.parseFlag(args, "--query");
    const tags = zmark.cli.parseFlag(args, "--tags");

    if (query == null and tags == null) {
        try stderr.writeAll("error: --query or --tags is required\n\n");
        try printSearchUsage(stderr);
        return;
    }
    const dataPath = try getDataPath(allocator);
    defer allocator.free(dataPath);

    var store = try zmark.Store.init(allocator, dataPath);
    defer store.deinit();

    var results: std.ArrayListUnmanaged(usize) = .{};
    defer results.deinit(allocator);

    try store.search(&results, query, tags);

    if (results.items.len == 0) {
        try stdout.writeAll("No bookmarks found for this filter\n");
    }
    for (results.items, 0..) |index, i| {
        try printBookmark(stdout, &store.bookmarks.items[index], i);
    }
}

fn handleList(allocator: std.mem.Allocator, stdout: *Writer, _: *Writer, args: []const []const u8) !void {
    if (hasFlag(args, "--help")) {
        try printListUsage(stdout);
        return;
    }
    const dataPath = try getDataPath(allocator);
    defer allocator.free(dataPath);

    var store = try zmark.Store.init(allocator, dataPath);
    defer store.deinit();

    if (store.bookmarks.items.len == 0) {
        try stdout.writeAll("No bookmarks found.\n");
    }
    for (store.bookmarks.items, 0..) |*bm, i| {
        try printBookmark(stdout, bm, i);
    }
}

fn handleGet(allocator: std.mem.Allocator, stdout: *Writer, stderr: *Writer, args: []const []const u8) !void {
    if (hasFlag(args, "--help")) {
        try printGetUsage(stdout);
        return;
    }
    const id = zmark.cli.parseFlag(args, "--id") orelse {
        try stderr.writeAll("error: --id is required\n\n");
        try printGetUsage(stderr);
        return;
    };

    const dataPath = try getDataPath(allocator);
    defer allocator.free(dataPath);

    var store = try zmark.Store.init(allocator, dataPath);
    defer store.deinit();

    const bm = store.getById(id) orelse {
        try stdout.print("No bookmard found for id {s}\n", .{id});
        return;
    };
    try printBookmark(stdout, bm, 0);
}

fn handleRemove(allocator: std.mem.Allocator, stdout: *Writer, stderr: *Writer, args: []const []const u8) !void {
    if (hasFlag(args, "--help")) {
        try printRemoveUsage(stdout);
        return;
    }
    const id = zmark.cli.parseFlag(args, "--id") orelse {
        try stderr.writeAll("error: --id is required\n\n");
        try printRemoveUsage(stderr);
        return;
    };

    const dataPath = try getDataPath(allocator);
    defer allocator.free(dataPath);

    var store = try zmark.Store.init(allocator, dataPath);
    defer store.deinit();

    const removed = store.remove(id);
    if (!removed) {
        try stdout.print("No bookmard found for id {s}\n", .{id});
        return;
    }
    try store.save();
    try stdout.print("Bookmard removed successfully with id {s}\n", .{id});
}
