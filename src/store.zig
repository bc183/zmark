const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

pub const BookmarkSource = enum {
    human,
    ai,

    pub fn fromString(str: ?[]const u8) ?BookmarkSource {
        const _str = str orelse &[_]u8{};
        const fields = @typeInfo(BookmarkSource).@"enum".fields;
        inline for (fields) |field| {
            if (std.mem.eql(u8, _str, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};

fn tagsContain(tags: []const []const u8, query: []const u8) bool {
    for (tags) |tag| {
        if (containsIgnoreCase(tag, query)) return true;
    }
    return false;
}

pub fn generateUlid() [26]u8 {
    const encoding = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

    // 6 bytes: millisecond timestamp
    const ts: u64 = @intCast(std.time.milliTimestamp());

    // 10 bytes: random
    var rand_bytes: [10]u8 = undefined;
    std.crypto.random.bytes(&rand_bytes);

    var out: [26]u8 = undefined;

    // Encode timestamp (first 10 chars, big-endian base32)
    var t = ts;
    var i: usize = 10;
    while (i > 0) {
        i -= 1;
        out[i] = encoding[@intCast(t & 0x1f)];
        t >>= 5;
    }

    // Encode randomness (last 16 chars)
    // Pack 10 random bytes into 80 bits, extract 5 bits at a time
    var rand_bits: u80 = 0;
    for (rand_bytes) |byte| {
        rand_bits = (rand_bits << 8) | byte;
    }
    i = 26;
    while (i > 10) {
        i -= 1;
        out[i] = encoding[@intCast(rand_bits & 0x1f)];
        rand_bits >>= 5;
    }

    return out;
}

fn toLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    if (needle.len == 0) return true;

    // Slide a window across haystack
    const end = haystack.len - needle.len + 1;
    for (0..end) |i| {
        var matched = true;
        for (0..needle.len) |j| {
            if (toLower(haystack[i + j]) != toLower(needle[j])) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

pub fn splitTags(allocator: std.mem.Allocator, input: []const u8) ![][]const u8 {
    if (input.len == 0) return &.{};

    // First pass: count how many tags
    var count: usize = 0;
    var it = std.mem.splitSequence(u8, input, ",");
    while (it.next()) |_| count += 1;

    // Allocate the slice
    const tags = try allocator.alloc([]const u8, count);

    // Second pass: fill it
    it = std.mem.splitSequence(u8, input, ","); // reset
    var i: usize = 0;
    while (it.next()) |tag| {
        tags[i] = std.mem.trim(u8, tag, " "); // trim whitespace
        i += 1;
    }

    return tags;
}

pub const Bookmark = struct {
    id: []const u8,
    url: []const u8,
    title: []const u8,
    tags: []const []const u8,
    notes: []const u8,
    source: BookmarkSource,
    created_at: i64,
    accessed_at: i64,
    hits: u32,

    const Self = @This();

    // init does NOT allocate. Returns temporary bookmark
    // with slices pointing into caller's memory.
    // store.add() will dupe everything.
    pub fn init(
        id: []const u8,
        url: []const u8,
        title: []const u8,
        parsedTags: []const []const u8,
        notes: ?[]const u8,
        source: BookmarkSource,
    ) Self {
        const now = std.time.timestamp();
        return Self{
            .id = id,
            .url = url,
            .title = title,
            .tags = parsedTags,
            .notes = notes orelse "",
            .source = source,
            .created_at = now,
            .accessed_at = now,
            .hits = 0,
        };
    }

    pub fn touch(self: *Self) void {
        self.accessed_at = std.time.timestamp();
        self.hits += 1;
    }

    pub fn hasTag(self: Self, needle: []const u8) bool {
        for (self.tags) |tag| {
            if (std.mem.eql(u8, tag, needle)) return true;
        }
        return false;
    }
};

pub const Store = struct {
    allocator: Allocator,
    bookmarks: std.ArrayListUnmanaged(Bookmark),
    file_path: []const u8,

    pub const JsonBookmark = struct {
        id: []const u8,
        url: []const u8,
        title: []const u8,
        tags: []const []const u8,
        notes: []const u8,
        source: []const u8,
        created_at: i64,
        accessed_at: i64,
        hits: u32,
    };

    const Self = @This();

    pub fn init(allocator: Allocator, file_path: []const u8) !Self {
        var store = Self{
            .allocator = allocator,
            .bookmarks = .{},
            .file_path = file_path,
        };
        try store.load();
        return store;
    }

    pub fn deinit(self: *Self) void {
        for (self.bookmarks.items) |bm| {
            self.freeBookmarkStrings(bm);
        }
        self.bookmarks.deinit(self.allocator);
    }

    pub fn add(self: *Self, bm: Bookmark) !void {
        try self.bookmarks.append(self.allocator, .{
            .id = try self.allocator.dupe(u8, bm.id),
            .url = try self.allocator.dupe(u8, bm.url),
            .title = try self.allocator.dupe(u8, bm.title),
            .notes = try self.allocator.dupe(u8, bm.notes),
            .source = bm.source,
            .tags = try self.dupeTags(bm.tags),
            .created_at = bm.created_at,
            .accessed_at = bm.accessed_at,
            .hits = bm.hits,
        });
    }

    pub fn remove(self: *Self, id: []const u8) bool {
        for (self.bookmarks.items, 0..) |bm, i| {
            if (std.mem.eql(u8, bm.id, id)) {
                self.freeBookmarkStrings(bm);
                _ = self.bookmarks.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn getById(self: Self, id: []const u8) ?*Bookmark {
        for (self.bookmarks.items) |*bm| {
            if (std.mem.eql(u8, bm.id, id)) return bm;
        }
        return null;
    }

    /// function to search bookmarks
    /// providing query will search in title, url and notes (OR contains)
    /// tags will search in tags (IN)
    /// providing both tags and query will result in AND condition
    pub fn search(self: Self, results: *std.ArrayListUnmanaged(usize), query: ?[]const u8, tags: ?[]const u8) !void {
        for (self.bookmarks.items, 0..) |*bm, i| {
            const query_match = if (query) |q|
                containsIgnoreCase(bm.url, q) or
                    containsIgnoreCase(bm.title, q) or
                    containsIgnoreCase(bm.notes, q)
            else
                true; // no query = match all

            const tags_match = if (tags) |t|
                tagsContain(bm.tags, t)
            else
                true; // no tags = match all

            if (query_match and tags_match) {
                try results.append(self.allocator, i);
            }
        }
    }

    fn dupeTags(self: *Self, tags: []const []const u8) ![]const []const u8 {
        const duped = try self.allocator.alloc([]const u8, tags.len);
        for (tags, 0..) |tag, i| {
            duped[i] = try self.allocator.dupe(u8, tag);
        }
        return duped;
    }

    fn freeBookmarkStrings(self: *Self, bm: Bookmark) void {
        self.allocator.free(bm.id);
        self.allocator.free(bm.url);
        self.allocator.free(bm.title);
        self.allocator.free(bm.notes);
        for (bm.tags) |tag| {
            self.allocator.free(tag);
        }
        self.allocator.free(bm.tags);
        // source is an enum — no allocation, nothing to free
    }

    pub fn save(self: Self) !void {
        if (std.fs.path.dirname(self.file_path)) |dir| {
            std.fs.makeDirAbsolute(dir) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }

        const file = try std.fs.createFileAbsolute(self.file_path, .{});
        defer file.close();

        var jbookmarks = try self.allocator.alloc(JsonBookmark, self.bookmarks.items.len);
        defer self.allocator.free(jbookmarks);

        for (self.bookmarks.items, 0..) |bm, i| {
            jbookmarks[i] = .{
                .id = bm.id,
                .url = bm.url,
                .title = bm.title,
                .tags = bm.tags,
                .notes = bm.notes,
                .source = @tagName(bm.source),
                .created_at = bm.created_at,
                .accessed_at = bm.accessed_at,
                .hits = bm.hits,
            };
        }

        var buf: [4096]u8 = undefined;
        var writer = file.writer(&buf);
        var jw: json.Stringify = .{
            .writer = &writer.interface,
        };
        try jw.write(jbookmarks);
        try writer.interface.flush();
    }

    pub fn load(self: *Self) !void {
        const content = std.fs.cwd().readFileAlloc(
            self.allocator,
            self.file_path,
            10 * 1024 * 1024,
        ) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer self.allocator.free(content);

        if (content.len == 0) return;

        const parsed = try json.parseFromSlice(
            []JsonBookmark,
            self.allocator,
            content,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();

        for (parsed.value) |jbm| {
            try self.bookmarks.append(self.allocator, .{
                .id = try self.allocator.dupe(u8, jbm.id),
                .url = try self.allocator.dupe(u8, jbm.url),
                .title = try self.allocator.dupe(u8, jbm.title),
                .notes = try self.allocator.dupe(u8, jbm.notes),
                .source = BookmarkSource.fromString(jbm.source) orelse .human,
                .tags = try self.dupeTags(jbm.tags),
                .created_at = jbm.created_at,
                .accessed_at = jbm.accessed_at,
                .hits = jbm.hits,
            });
        }
    }
};

