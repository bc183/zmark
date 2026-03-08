---
name: zmark
description: Save, search, and retrieve URL bookmarks using the zmark CLI tool. Use when you need to save a reference link for later, find a previously saved URL or documentation, list saved bookmarks by tag, or manage a persistent collection of useful links.
---

# zmark — Bookmark Manager CLI

A terminal bookmark manager. Bookmarks are stored as JSON in `~/.local/share/zmark/bookmarks.json`. Each bookmark has a ULID, URL, title, tags, notes, and a source field.

## Adding bookmarks

```bash
zmark add --url <url> --title <title> --tags "tag1,tag2" --notes "why this is useful" --source ai
```

- `--url` and `--title` are required
- `--tags` is comma-separated, optional
- `--notes` is free-form, optional
- `--source` should be `ai` when you are saving bookmarks. Defaults to `human`

## Searching bookmarks

```bash
# Search by keyword (matches title, url, and notes, case-insensitive)
zmark search --query "allocator"

# Filter by tag
zmark search --tags "zig"

# Both together (AND condition)
zmark search --query "memory" --tags "zig"
```

## Listing bookmarks

```bash
# List all
zmark list
```

## Getting a specific bookmark

```bash
zmark get --id 01J5K3ABCDEFGHJKMNPQRSTVWX
```

## Removing a bookmark

```bash
zmark rm --id 01J5K3ABCDEFGHJKMNPQRSTVWX
```

## Rules

- Always use `--source ai` when saving bookmarks
- Tags are comma-separated with no spaces: `--tags "zig,docs,reference"`
- IDs are 26-character ULIDs printed when a bookmark is added
- Search is case-insensitive and matches across title, URL, and notes
