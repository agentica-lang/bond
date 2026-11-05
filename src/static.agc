## Static files: a folder served under a path, answered by `Files.respond` (typed with `std/mime`), with the small
## files kept in memory.

import MIME from "std/mime"
import URI from "std/uri"
import Conns from "conn"
import Dates from "dates"
import Files from "files"
import Pattern from "pattern"
import {Conn} from "conn"

## The largest `max_bytes`, 1 TiB: no real file is bigger, and the number stays far from the end of an `Int`.
export MAX_FILE_BYTES = 1_099_511_627_776

## The reason of the `error` of `serve` for a request that is not for a file. Any other `error` is a failure.
export MISS = "not a static file"

# Names that Windows opens as a device, whatever the extension and the case.
DEVICES = Set.new([
  "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2",
  "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
])

DIGITS = Set.new(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
LETTERS = Set.new(["a", "b", "c", "d", "e", "f"])

# The length of the digest in a fingerprinted name: 8 hex digits (a short hash) to 64 (a SHA-256).
FINGERPRINT_MIN = 8
FINGERPRINT_MAX = 64

# The shortest and the longest file that is compressed when no `.gz` file is next to it: below 256 bytes the gzip
# header costs about what it saves, and `Zlib.gzip` takes at most 1 MiB.
GZIP_MIN_BYTES = 256
GZIP_MAX_BYTES = 1_048_576

# What a cached entry weighs besides its bytes: the key, the headers, the tables.
ENTRY_OVERHEAD = 512

# The key of the byte count in `Mount.used`.
USED = "bytes"

## The files of the folder `root` (a real path) are served under the path `prefix`; a file over `max_bytes` is not
## served. `max_age` is the seconds that a cache may keep a file (0 is "ask each time"). With `fingerprint`, a name that
## has a fingerprint is kept for a year, whatever `max_age` is. A file of at most `piece_bytes` is read in one call,
## and kept in `entries` while `cache_bytes` (0: not at all) allows it, with `used` counting the bytes.
export struct Mount
  prefix: String
  root: String
  max_bytes: Int
  max_age: Int
  fingerprint: Bool
  cache_bytes: Int
  piece_bytes: Int
  entries: ATS[String, Entry]
  used: ATS[String, Int]
end

## The bytes of a file as one answer sends them, with what the answer says about them.
export struct Variant
  rep: Files.Rep
  body: Bytes
end

## A small file in memory: the path that `stat` checks (the folder joined with the names of the request, so a link is
## followed), the `size` and `modified` seconds it had when it was read, the bytes, and the compressed ones when the
## type is text and compression gave something smaller. A `trusted` entry (a fingerprinted name of a mount with
## `fingerprint`, which the app promises never changes) is not checked against the disk at all.
export struct Entry
  path: String
  size: Int
  modified: Int
  plain: Variant
  zipped: Optional[Variant]
  trusted: Bool
  cost: Int
end

# The file that the request names: the folder joined with the names (what `stat` follows, as the cache checks it),
# the real path that was checked and read, and its `stat`.
struct Located
  joined: String
  file: String
  info: FileInfo
end

## The mount of the folder `root` (a real path) under `prefix`, with an empty cache of `cache_bytes`.
export def make_mount(
  prefix: String,
  root: String,
  max_bytes: Int,
  max_age: Int,
  fingerprint: Bool,
  cache_bytes: Int,
  piece_bytes: Int,
) -> Mount
  entries: ATS[String, Entry] = ATS.new()
  used: ATS[String, Int] = ATS.new()
  return Mount(
    prefix: prefix,
    root: root,
    max_bytes: max_bytes,
    max_age: max_age,
    fingerprint: fingerprint,
    cache_bytes: cache_bytes,
    piece_bytes: piece_bytes,
    entries: entries,
    used: used,
  )
end

## The real path of the folder of a mount, when it is a folder. It is read once, when the app is built.
export def real_root(root: String) -> Result[String]
  info = try File.stat(root)
  if info.kind != "directory"
    return error("not a folder")
  end

  return Path.real(root)
end

## The answer of the first mount that holds the path of the request: a file (200), or a 405 for a method other than
## GET and HEAD. An `error` with the reason `MISS` means that the request is not for a file (nothing of that name, a
## folder, a hidden name, a way out of the folder), so the caller answers it as a path with no route. Any other
## `error` is a file that cannot be sent (too big, or not readable), for the error handler.
export def serve(mounts: List[Mount], conn: Conn) -> Result[Conn]
  for mount in mounts
    inside = below(mount, conn.path)
    if inside.ok?
      return answer(mount, inside.unwrap!, conn)
    end
  end

  return error(MISS)
end

# The segments of the path after the prefix of the mount, as the client sent them (not decoded), when there is at least
# one. Prefix and path are compared segment by segment, so /assetsx is not under /assets.
def below(mount: Mount, path: String) -> Result[List[String]]
  wanted = Pattern.segments(mount.prefix)
  found = Pattern.segments(path)
  if found.size <= wanted.size
    return error(MISS)
  end

  for i in 0...wanted.size
    if wanted[i] != found[i]
      return error(MISS)
    end
  end

  return ok(found.drop(wanted.size))
end

def answer(mount: Mount, parts: List[String], conn: Conn) -> Result[Conn]
  if conn.method != "GET" and conn.method != "HEAD"
    return ok(Conns.halt(Conns.header(conn, "allow", "GET, HEAD"), 405, "method not allowed"))
  end

  # The path as the client wrote it is the key: only the names that passed the checks of `decode` and `locate` get an
  # entry, so a hit skips them, and the `stat` of the entry is the only call to the disk.
  key = parts.join("/")
  case cached(mount, key)
    some(entry) -> return reply(conn, entry)
    none -> nil
  end

  names = try decode(parts)
  found = try locate(mount, names)
  return send_found(mount, key, found, names.last, conn)
end

# Each segment is decoded, and then refused when it could leave the folder or name something that is not a plain file
# of it: an empty name, a name that starts with a dot (`..` and the files that are hidden), a slash, a backslash, a
# colon (a drive of Windows), a control character (NUL included) or the name of a device of Windows. So `%2e%2e`,
# `%2F` and `%5C` are refused too, and `%252e` is only a name with a percent sign.
def decode(parts: List[String]) -> Result[List[String]]
  names: List[String] = []
  for part in parts
    decoded = try miss(URI.decode_uri_component(part))
    if decoded.empty? or decoded.start_with?(".") or device?(decoded) or decoded.split("").any? do |ch| unsafe?(ch) end
      return error(MISS)
    end

    names = names.push(decoded)
  end

  return ok(names)
end

def unsafe?(ch: String) -> Bool
  code = ch.code
  return code < 32 or code == 127 or ch == "/" or ch == "\\" or ch == ":"
end

def device?(name: String) -> Bool
  return DEVICES.include?(name.split(".")[0].strip.upcase)
end

# Any failure of the lookup is a miss: the client learns nothing about why a path is not a file.
def miss(result: Result[String]) -> Result[String]
  if result.ok?
    return result
  end

  return error(MISS)
end

# The real path of the file, with the links followed, when it is a plain file inside the real folder and no name of
# its path below the folder starts with a dot: so a link to `.env` or into `.git/` is a miss like the dot file itself.
# A link that leads out of the folder is a miss. The file can still change between this check and the read.
def locate(mount: Mount, names: List[String]) -> Result[Located]
  joined = try miss(Path.join(List.concat([mount.root], names)))
  file = try miss(Path.real(joined))
  start = with_separator(mount.root)
  if not file.start_with?(start)
    return error(MISS)
  end

  below_root = file.slice(start.length, file.length - start.length).replace("\\", "/")
  if below_root.split("/").any? do |part| part.start_with?(".") end
    return error(MISS)
  end

  info = File.stat(file)
  if not info.ok? or info.unwrap!.kind != "file"
    return error(MISS)
  end

  return ok(Located(joined: joined, file: file, info: info.unwrap!))
end

def with_separator(root: String) -> String
  if root.end_with?("/") or root.end_with?("\\")
    return root
  end

  if root.include?("\\")
    return "#{root}\\"
  end

  return "#{root}/"
end

# The reasons are for stderr and the error handler, in words: the text of a failed read is the VM's, not ours. The
# size is checked here with the `stat` of `locate`. A file of at most one piece (`piece_bytes`) is read whole, and kept
# when the mount has a cache; a bigger one is sent by `Files.respond`, which reads it in pieces, so a big file costs no
# memory.
def send_found(mount: Mount, key: String, found: Located, name: String, conn: Conn) -> Result[Conn]
  size = found.info.size_bytes
  if size > mount.max_bytes
    return error("the static file #{name} is over #{mount.max_bytes} bytes")
  end

  text = MIME.text?(MIME.mime_type(name))
  described = Files.describe(name, none, found.info, cache_control(mount, name))
  plain = described.with(vary: text, piece_bytes: mount.piece_bytes)
  if size <= mount.piece_bytes and mount.cache_bytes > 0
    trusted = mount.fingerprint and fingerprinted?(name)
    entry = try load(mount, found, name, plain, trusted)
    remember(mount, key, entry)
    return reply(conn, entry)
  end

  if text and accepts_gzip?(conn) and not Files.ranged?(conn)
    case sibling(found)
      some(twin) ->
        packed = described.with(vary: true, piece_bytes: mount.piece_bytes)
        return sent(Files.respond(conn, zipped_of(packed, twin), twin_path(found), none), name)
      none -> nil
    end
  end

  return sent(Files.respond(conn, plain, found.file, none), name)
end

def sent(result: Result[Conn], name: String) -> Result[Conn]
  if not result.ok?
    return error("the static file #{name} cannot be read")
  end

  return result
end

# The entry of a small file: its bytes, and the compressed ones when its type is text.
def load(mount: Mount, found: Located, name: String, plain: Files.Rep, trusted: Bool) -> Result[Entry]
  bytes = try read_file(found.file, plain.size, name)
  zipped: Optional[Variant] = none
  if plain.vary
    zipped = compressed(mount, found, plain, bytes)
  end

  cost = bytes.size + ENTRY_OVERHEAD
  case zipped
    some(variant) -> cost = cost + variant.body.size
    none -> nil
  end

  return ok(
    Entry(
      path: found.joined,
      size: plain.size,
      modified: plain.modified,
      plain: Variant(rep: plain, body: bytes),
      zipped: zipped,
      trusted: trusted,
      cost: cost,
    ),
  )
end

def read_file(file: String, size: Int, name: String) -> Result[Bytes]
  read = Files.read_whole(file, size)
  if not read.ok?
    return error("the static file #{name} cannot be read")
  end

  return read
end

# The compressed form of a small text file: the `.gz` file next to it when there is a fresh one, else the bytes
# compressed once here. `none` when it would not be smaller.
def compressed(mount: Mount, found: Located, plain: Files.Rep, bytes: Bytes) -> Optional[Variant]
  case sibling(found)
    some(twin) ->
      if twin.size_bytes <= mount.piece_bytes
        read = Files.read_whole(twin_path(found), twin.size_bytes)
        if read.ok?
          return some(Variant(rep: zipped_of(plain, twin), body: read.unwrap!))
        end
      end

    none -> nil
  end

  if bytes.size < GZIP_MIN_BYTES or bytes.size > GZIP_MAX_BYTES
    return none
  end

  packed = Zlib.gzip(bytes)
  if not packed.ok? or packed.unwrap!.size >= bytes.size
    return none
  end

  rep = plain.with(etag: gzip_tag(plain.etag), size: packed.unwrap!.size, encoding: "gzip")
  return some(Variant(rep: rep, body: packed.unwrap!))
end

# The `.gz` file next to the file, when it is a plain file with bytes in it that is not older than the file: a build
# that compresses its files leaves it, and one that left it behind an edit of the file is not served.
def sibling(found: Located) -> Optional[FileInfo]
  twin = File.stat(twin_path(found))
  if not twin.ok? or twin.unwrap!.kind != "file" or twin.unwrap!.size_bytes == 0
    return none
  end

  if twin.unwrap!.modified_seconds < found.info.modified_seconds
    return none
  end

  return some(twin.unwrap!)
end

def twin_path(found: Located) -> String
  return "#{found.file}.gz"
end

# The `Rep` of the `.gz` file `twin` as the answer for the file that `plain` describes: its own size, time and tag.
def zipped_of(plain: Files.Rep, twin: FileInfo) -> Files.Rep
  return plain.with(
    etag: gzip_tag("\"#{twin.size_bytes}-#{twin.modified_seconds}\""),
    modified: twin.modified_seconds,
    last_modified: Dates.format(twin.modified_seconds),
    size: twin.size_bytes,
    encoding: "gzip",
  )
end

# A tag that differs from the one of the same file as it is, since the bytes differ.
def gzip_tag(tag: String) -> String
  return "#{tag.slice(0, tag.length - 1)}-gz\""
end

# The answer for an entry: its compressed bytes for a client that takes gzip and asks for the whole file (a part of a
# compressed file is not a part of the file), else the bytes as they are.
def reply(conn: Conn, entry: Entry) -> Result[Conn]
  case entry.zipped
    some(variant) ->
      if accepts_gzip?(conn) and not Files.ranged?(conn)
        return Files.respond(conn, variant.rep, entry.path, some(variant.body))
      end

    none -> nil
  end

  return Files.respond(conn, entry.plain.rep, entry.path, some(entry.plain.body))
end

# Whether `Accept-Encoding` lists gzip with a quality above 0 (`gzip;q=0` refuses it).
def accepts_gzip?(conn: Conn) -> Bool
  header = Conns.request_header(conn, "accept-encoding").unwrap_or("")
  return header.split(",").any? do |item| gzip_item?(item) end
end

def gzip_item?(item: String) -> Bool
  parts = item.split(";").map do |part| part.strip.downcase end
  if parts[0] != "gzip" and parts[0] != "x-gzip"
    return false
  end

  return not parts.drop(1).any? do |param| zero_quality?(param) end
end

def zero_quality?(param: String) -> Bool
  if not param.start_with?("q=")
    return false
  end

  value = param.slice(2, param.length - 2)
  return not value.empty? and value.split("").all? do |ch| ch == "0" or ch == "." end
end

# The entry of the key when the file is the one it was made from: a `stat` with the same size and time of change (none
# for a trusted entry). An edit that keeps both (inside one second) is not seen, as with the `ETag`; a file that
# is gone
# or changed is dropped and the request goes the long way.
def cached(mount: Mount, key: String) -> Optional[Entry]
  if mount.cache_bytes == 0
    return none
  end

  found = mount.entries.get(key)
  if not found.ok?
    return none
  end

  entry = found.unwrap!
  if entry.trusted or unchanged?(entry)
    return some(entry)
  end

  mount.entries.delete(key)
  return none
end

def unchanged?(entry: Entry) -> Bool
  info = File.stat(entry.path)
  if not info.ok? or info.unwrap!.kind != "file"
    return false
  end

  return info.unwrap!.size_bytes == entry.size and info.unwrap!.modified_seconds == entry.modified
end

# Keeps the entry unless it is over half the budget. When the bytes would pass the budget the cache is emptied first:
# no order of eviction to keep, and a file that is asked for again is read again once. The count is approximate under
# concurrent misses (a replaced entry is counted twice until the next emptying, and a task that empties may lose the
# count of another), which errs towards emptying early, and the memory stays within the budget plus the entries that
# were added at that moment.
def remember(mount: Mount, key: String, entry: Entry) -> Void
  if entry.cost > mount.cache_bytes / 2
    return
  end

  total = mount.used.add(USED, entry.cost)
  if total > mount.cache_bytes
    for stale in mount.entries.keys
      mount.entries.delete(stale)
    end

    mount.used.put(USED, entry.cost)
  end

  mount.entries.put(key, entry)
end

# With `fingerprint` on, the app says that a name with a fingerprint never changes its content, so it is cached for as
# long as allowed and never asked for again. The others are cached for the `max_age` of the mount: 0 asks the server
# each time, which is a cheap 304 now.
def cache_control(mount: Mount, name: String) -> String
  if mount.fingerprint and fingerprinted?(name)
    return "public, max-age=#{Files.MAX_AGE_SECONDS}, immutable"
  end

  if mount.max_age == 0
    return "no-cache"
  end

  return "public, max-age=#{mount.max_age}"
end

# `app.3f9a1c2b.css`, `app-3f9a1c2b.css` and `main.3f9a1c2b.chunk.js`: a part of 8 to 64 lowercase hex digits between
# the first part of the name and the extension, with at least one letter and one digit, so a date (`20240131`) or a
# Unix time (`1712345678`) is not a fingerprint, nor a word (`deadbeef`). A name with no extension has none.
def fingerprinted?(name: String) -> Bool
  parts = name.replace("-", ".").split(".")
  if parts.size < 3
    return false
  end

  return parts.drop(1).take(parts.size - 2).any? do |part| hex_digest?(part) end
end

def hex_digest?(part: String) -> Bool
  if part.length < FINGERPRINT_MIN or part.length > FINGERPRINT_MAX
    return false
  end

  chars = part.split("")
  hex = chars.all? do |ch| DIGITS.include?(ch) or LETTERS.include?(ch) end
  digit = chars.any? do |ch| DIGITS.include?(ch) end
  letter = chars.any? do |ch| LETTERS.include?(ch) end
  return hex and digit and letter
end
