# zmark

A bookmark manager that works from the terminal. Built for humans and AI agents.

zmark stores bookmarks as JSON in `~/.local/share/zmark/bookmarks.json`. No database, no daemon, no config file. Each bookmark gets a ULID so it's sortable by time and globally unique.

## Install

### Quick install

```
curl -fsSL https://raw.githubusercontent.com/bc183/zmark/main/install.sh | sh
```

Detects your OS and architecture, lets you pick a version, and installs the binary to `/usr/local/bin`.

### Manual download

Grab the latest binary from the [releases page](https://github.com/bc183/zmark/releases) and put it somewhere on your `$PATH`:

```
curl -L https://github.com/bc183/zmark/releases/latest/download/zmark-x86_64-linux.tar.gz | tar xz
sudo mv zmark /usr/local/bin/
```

### Build from source

Requires Zig 0.15.2+.

```
zig build
```

Binary ends up in `zig-out/bin/zmark`.

## Usage

```
zmark <command> [options]
```

### Add a bookmark

```
zmark add --url https://ziglang.org --title "Zig Language" --tags "lang,systems" --notes "check out the stdlib"
```

`--url` and `--title` are required. `--tags`, `--notes`, and `--source` are optional. `--source` defaults to `human` (the other option is `ai`).

### List all bookmarks

```
zmark list
```

### Get a bookmark by ID

```
zmark get --id 01J5K3...
```

### Search

```
zmark search --query "zig"
zmark search --tags "systems"
zmark search --query "zig" --tags "lang"
```

`--query` searches across title, URL, and notes (case-insensitive). `--tags` filters by tag. Both together is an AND.

### Remove a bookmark

```
zmark rm --id 01J5K3...
```

### Version

```
zmark version
```

### Help

```
zmark help
zmark add --help
zmark search --help
```

Every subcommand supports `--help`.

## Claude Code skill

zmark ships with a skill file that lets Claude Code save and retrieve bookmarks on your behalf. To install it:

```
mkdir -p ~/.claude/skills/zmark
cp skill.md ~/.claude/skills/zmark/SKILL.md
```

After that, Claude Code can use zmark commands directly during conversations — bookmarking URLs, searching your collection, etc.

## Storage format

Bookmarks are stored as a JSON array. Each entry looks like:

```json
{
  "id": "01J5K3ABCDEFGHJKMNPQRSTVWX",
  "url": "https://ziglang.org",
  "title": "Zig Language",
  "tags": ["lang", "systems"],
  "notes": "check out the stdlib",
  "source": "human",
  "created_at": 1720000000,
  "accessed_at": 1720000000,
  "hits": 0
}
```

## License

MIT. See [LICENSE](LICENSE).
