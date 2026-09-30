---
title: Log File Reader
type: component
sources: [S036]
updated: 2026-09-23
---

# Log File Reader

`RedmineAiHelper::Util::LogFileReader` does the file I/O behind the
[log file access tools](./log-file-access-tools.md): `#info`, `#tail` and
`#search`. It depends on no external state, which keeps its tests simple; the
file it reads comes from [Log File Location
Resolution](./log-file-location-resolution.md) (S036). Targets are 1 GB tail in
≤ 5 s and search of ≥ 10 GB logs in ≤ 30 s (S036).

## Tail: read backward, never the whole file

Open the file **once** (`"rb"`), cap reading at the size seen at open time, and
`IO#pread` 64 KB chunks backward from the end until *requested lines + 1*
newlines are found or the start is reached (S036). Consequences (S036):

- Bytes read scale with lines requested, not file size.
- A final line with no trailing newline (mid-write) is still returned.
- Appends during the read are ignored, not an error.
- Rotation (rename) mid-read is harmless: the open descriptor keeps reading the
  same inode.

**Rejected**: `File.foreach`/`readlines` (reads everything); shelling out to
`tail`/`grep` via `Open3` (command-injection surface, environment-dependent, and
UTF-8/line-length/line-number handling would have to be redone in Ruby anyway);
adding a gem such as `elif` for a few dozen lines (S036).

## Search: newest first, with two stop conditions

Read backward in 1 MB chunks, carrying a line cut at a chunk boundary into the
next (older) chunk; scan each chunk's lines newest-first (S036).

- **Literal match**: `Regexp.new(Regexp.escape(keyword), case_sensitive ? nil :
  Regexp::IGNORECASE)` + `match?` — special characters are literal, default is
  case-insensitive, and no regex injection or ReDoS is possible (S036). A
  whole-chunk `match?` runs first; chunks without a hit skip line splitting
  (S036). `downcase` + `include?` was rejected because it copies every line
  (S036).
- **Context**: because scanning runs newest-first, the last `context_lines`
  lines seen become *after*, and the next ones read become *before*.
  Overlapping contexts are not deduplicated (KISS) (S036).
- **Stops** at `max_matches + 1` hits (→ `truncated: true`, return the newest
  `max_matches`) or after 500 MB (`524_288_000` bytes) scanned (S036).
- **Partial first line**: if the 500 MB boundary lands mid-line, that line is
  dropped rather than matched, to avoid false hits and shifted numbering (S036).
- Results report `scanned_bytes`, `file_size_bytes`, `scanned_whole_file`, and
  are re-sorted oldest→newest because logs read chronologically (S036).

**Rejected**: forward-scanning the last 500 MB with a ring buffer — simpler, but
it always reads 500 MB and cannot stop early at the match limit (S036).

## Line numbers (user-confirmed trade-off)

The spec wanted line numbers counted from the file start, but counting them
requires reading every unread newline — proportional to file size, which
conflicts with the tail and 30 s search limits (S036). Decision (S036):

- `line_number` (1-based from start) only when the read reached the file start;
  otherwise `null`.
- `lines_from_end` (last line = 1) on every line, always.
- `line_numbering: "from_start" | "from_end_only"` so the LLM can't confuse the
  two.

Rejected: from-end only (numbers shift as the log grows), and always from-start
(5–10 s on 10 GB) (S036).

## Output shaping

- Invalid UTF-8 → `String#scrub("�")` (S036).
- Lines are cut at 2,000 characters with ` …[truncated N chars]` and
  `truncated: true` on the line object (S036).
- Chunk sizes and the 500 MB cap are constructor arguments (`max_scan_bytes:`,
  defaulting to the spec constants) so tests can prove the cut-off without
  creating huge files (S036).

## Related

- [Log File Access Tools](./log-file-access-tools.md) ·
  [Log File Location Resolution](./log-file-location-resolution.md)
