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
MAX_FILE_BYTES = 1_099_511_627_776

## The reason of the `error` of `serve` for a request that is not for a file. Any other `error` is a failure.
MISS = "not a static file"

## The files of the folder `root` (a real path) are served under the path `prefix`; a file over `max_bytes` is not
## served. `max_age` is the seconds that a cache may keep a file (0 is "ask each time"). With `fingerprint`, a name that
## has a fingerprint is kept for a year, whatever `max_age` is. A file of at most `piece_bytes` is read in one call,
## and kept in `entries` while `cache_bytes` (0: not at all) allows it, with `used` counting the bytes.
struct Mount
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

## A small file in memory: the path that `stat` checks (the folder joined with the names of the request), the `size`
## and `modified` seconds it had when it was read, its `rep` and `body`, and the same for the `.gz` file next to it when
## there was a fresh one (`zipped` and `zipped_body`). `twin` is what `stat` said of the `.gz` path when the entry was
## made ("" for no file, else its size and time), so a `.gz` that is rewritten, removed or added later is seen. A `trusted` entry (a fingerprinted name of a mount with
## `fingerprint`, which the app promises never changes) is not checked against the disk at all.
struct Entry
  id: Int
  path: String
  size: Int
  modified: Int
  rep: Files.Rep
  body: Bytes
  zipped: Optional[Files.Rep]
  zipped_body: Bytes
  twin: String
  trusted: Bool
  cost: Int
end

## The mount of the folder `root` (a real path) under `prefix`, with an empty cache of `cache_bytes`.
def make_mount(
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
  Mount(
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
def real_root(root: String) -> Result[String]
  info = try File.stat(root)
  return error("not a folder") if info.kind != "directory"

  Path.real(root)
end

## The answer of the first mount that holds the path of the request: a file (200), or a 405 for a method other than
## GET and HEAD. An `error` with the reason `MISS` means that the request is not for a file (nothing of that name, a
## folder, a hidden name, a way out of the folder), so the caller answers it as a path with no route. Any other
## `error` is a file that cannot be sent (too big, or not readable), for the error handler.
def serve(mounts: List[Mount], conn: Conn) -> Result[Conn]
  for mount in mounts
    inside = below(mount, conn.path)
    return answer(mount, inside.unwrap!, conn) if inside.ok?
  end

  error(MISS)
end

private

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

# What a cached entry weighs besides its bytes: the key, the headers, the tables.
ENTRY_OVERHEAD = 512

# The keys of `Mount.used`: the byte count, the last id of an entry, and the prefix of the claim on an entry that is
# dropped (the task that makes the claim 1 drops it and gives its bytes back, so two tasks never do it twice).
USED = "bytes"

IDS = "ids"

GONE = "gone"

# The file that the request names: the folder joined with the names (what `stat` follows, as the cache checks it), the
# real path that was checked and read, that path below the folder (with `/`), and its `stat`.
struct Located
  joined: String
  file: String
  relative: String
  info: File.Info
end

# The segments of the path after the prefix of the mount, as the client sent them (not decoded), when there is at least
# one. Prefix and path are compared segment by segment, so /assetsx is not under /assets.
def below(mount: Mount, path: String) -> Result[List[String]]
  wanted = Pattern.segments(mount.prefix)
  found = Pattern.segments(path)
  return error(MISS) if found.size <= wanted.size

  for i in 0...wanted.size
    return error(MISS) if wanted[i] != found[i]
  end

  ok(found.drop(wanted.size))
end

def answer(mount: Mount, parts: List[String], conn: Conn) -> Result[Conn]
  if conn.method != "GET" and conn.method != "HEAD"
    return ok(Conns.halt(Conns.header(conn, "allow", "GET, HEAD"), 405, "method not allowed"))
  end

  # The path as the client wrote it is looked up, and only a path that is the real name of its file is ever stored (see
  # `send_found`), so a hit skips `decode` and `locate`: it costs the `stat` of the file, and for a text file and
  # a client
  # that takes gzip the `stat` of its `.gz` path too.
  case cached(mount, parts.join("/"), conn)
    some(entry) -> return reply(conn, entry)
    none -> nil
  end

  names = try decode(parts)
  found = try locate(mount, names)
  # Not `names`, which are decoded: `%62ig.css` is another spelling of `big.css`, and only the real name is a key.
  send_found(mount, found, names.last, found.relative == parts.join("/"), conn)
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

  ok(names)
end

def unsafe?(ch: String) -> Bool
  code = ch.code
  code < 32 or code == 127 or ch == "/" or ch == "\\" or ch == ":"
end

def device?(name: String) -> Bool = DEVICES.include?(name.split(".")[0].strip.upcase)

# Any failure of the lookup is a miss: the client learns nothing about why a path is not a file.
def miss(result: Result[String]) -> Result[String]
  return result if result.ok?

  error(MISS)
end

# The real path of the file, with the links followed, when it is a plain file inside the real folder and no name of
# its path below the folder starts with a dot: so a link to `.env` or into `.git/` is a miss like the dot file itself.
# A link that leads out of the folder is a miss. The file can still change between this check and the read.
def locate(mount: Mount, names: List[String]) -> Result[Located]
  joined = try miss(Path.join(List.concat([mount.root], names)))
  file = try miss(Path.real(joined))
  relative = try inside(mount, file)
  info = File.stat(file)
  return error(MISS) if not info.ok? or info.unwrap!.kind != "file"

  ok(Located(joined: joined, file: file, relative: relative, info: info.unwrap!))
end

# The real path of a file below the real folder, with `/`, when it is inside it and no name of it starts with a dot.
def inside(mount: Mount, file: String) -> Result[String]
  start = with_separator(mount.root)
  return error(MISS) if not file.start_with?(start)

  below_root = file.slice(start.length, file.length - start.length).replace("\\", "/")
  return error(MISS) if below_root.split("/").any? do |part| part.start_with?(".") end

  ok(below_root)
end

def with_separator(root: String) -> String
  return root if root.end_with?("/") or root.end_with?("\\")

  return "#{root}\\" if root.include?("\\")

  "#{root}/"
end

# The reasons are for stderr and the error handler, in words: the text of a failed read is the VM's, not ours. The
# size is checked here with the `stat` of `locate`. A file of at most one piece (`piece_bytes`) that fits the cache is
# read whole by a `GET` and kept; any other is answered by `Files.respond`, which reads a small one whole and a big
# one in pieces, so a big file costs no memory. An entry is stored only under the real name of its file (not `%62ig`,
# `Big` on a folder that ignores the case, or a link), so one file has one entry, and no spelling of a name makes more.
def send_found(mount: Mount, found: Located, name: String, canonical: Bool, conn: Conn) -> Result[Conn]
  size = found.info.size_bytes
  return error("the static file #{name} is over #{mount.max_bytes} bytes") if size > mount.max_bytes

  text = MIME.text?(MIME.mime_type(name))
  described = Files.describe(name, none, found.info, cache_control(mount, name))
  plain = described.with(vary: text, piece_bytes: mount.piece_bytes)
  gzip = text and accepts_gzip?(conn) and not Files.ranged?(conn)
  if size <= mount.piece_bytes and size + ENTRY_OVERHEAD <= mount.cache_bytes / 2 and conn.method == "GET"
    near: Optional[Located] = none
    if text
      near = sibling(mount, found)
    end

    if keeps?(mount, size, near)
      trusted = mount.fingerprint and fingerprinted?(name)
      entry = try load(mount, found, plain, near, trusted)
      if canonical
        remember(mount, found.relative, entry)
      end

      return reply(conn, entry)
    end

    return send_uncached(mount, found, plain, near, gzip, conn)
  end

  far: Optional[Located] = none
  if gzip
    far = sibling(mount, found)
  end

  send_uncached(mount, found, plain, far, gzip, conn)
end

# Whether the entry of a file of `size` bytes with this `.gz` file fits the cache. A `.gz` file that does not (over
# `piece_bytes`, or taking the entry over half of the budget) is not loaded into memory: the file is not kept, and a
# `.gz` is sent from the disk by `send_uncached`.
def keeps?(mount: Mount, size: Int, twin: Optional[Located]) -> Bool
  case twin
    some(found) ->
      packed = found.info.size_bytes
      packed <= mount.piece_bytes and size + packed + ENTRY_OVERHEAD <= mount.cache_bytes / 2

    none -> true
  end
end

def send_uncached(
  mount: Mount,
  found: Located,
  plain: Files.Rep,
  twin: Optional[Located],
  gzip: Bool,
  conn: Conn,
) -> Result[Conn]
  if gzip
    case twin
      some(zipped) ->
        # A `.gz` file that changes after the check is not an error: the file as it is answers.
        served = Files.respond(conn, zipped_of(plain, zipped.info), zipped.file, none)
        return served if served.ok?

      none -> nil
    end
  end

  sent = Files.respond(conn, plain, found.file, none)
  return error("the static file #{found.relative} cannot be read") if not sent.ok?

  sent
end

# The entry of a small file: its bytes, and the `.gz` file next to it when there is one (`keeps?` says it fits),
# read at
# the same time. A `.gz` file that cannot be read is left out.
def load(mount: Mount, found: Located, plain: Files.Rep, twin: Optional[Located], trusted: Bool) -> Result[Entry]
  read = Files.read_whole(found.file, plain.size)
  return error("the static file #{found.relative} cannot be read") if not read.ok?

  bytes = read.unwrap!
  zipped: Optional[Files.Rep] = none
  packed = "".bytes
  stamp = ""
  if plain.vary
    stamp = twin_stamp(found.joined)
  end

  case twin
    some(zip) ->
      zip_read = Files.read_whole(zip.file, zip.info.size_bytes)
      if zip_read.ok?
        zipped = some(zipped_of(plain, zip.info))
        packed = zip_read.unwrap!
      end

    none -> nil
  end

  ok(
    Entry(
      id: mount.used.add(IDS, 1),
      path: found.joined,
      size: plain.size,
      modified: plain.modified,
      rep: plain,
      body: bytes,
      zipped: zipped,
      zipped_body: packed,
      twin: stamp,
      trusted: trusted,
      cost: bytes.size + packed.size + ENTRY_OVERHEAD,
    ),
  )
end

# What `stat` says of the `.gz` path of a file, as the cache compares it: "" when there is no file, else its size and
# time of change. The path is the one that the request joined, with links followed, whatever `sibling` makes of it.
def twin_stamp(joined: String) -> String
  info = File.stat("#{joined}.gz")
  return "" if not info.ok? or info.unwrap!.kind != "file"

  "#{info.unwrap!.size_bytes}-#{info.unwrap!.modified_seconds}"
end

# The `.gz` file next to the file, when it is a plain file with bytes in it, not older than the file, and inside the
# folder by the same rules as the file (a link to a file outside, or to a hidden one, is not served): a build that
# compresses its files leaves it, and one that was left behind an edit of the file is not served.
def sibling(mount: Mount, found: Located) -> Optional[Located]
  real = Path.real("#{found.file}.gz")
  return none if not real.ok?

  relative = inside(mount, real.unwrap!)
  return none if not relative.ok?

  twin = File.stat(real.unwrap!)
  return none if not twin.ok? or twin.unwrap!.kind != "file" or twin.unwrap!.size_bytes == 0

  return none if twin.unwrap!.size_bytes > mount.max_bytes

  return none if twin.unwrap!.modified_seconds < found.info.modified_seconds

  some(Located(joined: "#{found.joined}.gz", file: real.unwrap!, relative: relative.unwrap!, info: twin.unwrap!))
end

# The `Rep` of the `.gz` file whose `stat` is `twin` as the answer for the file that `plain` describes: its own size,
# time and tag, since the bytes differ.
def zipped_of(plain: Files.Rep, twin: File.Info) -> Files.Rep
  tag = "\"#{twin.size_bytes}-#{twin.modified_seconds}-gz\""
  plain.with(
    etag: tag,
    modified: twin.modified_seconds,
    last_modified: Dates.format(twin.modified_seconds),
    size: twin.size_bytes,
    encoding: "gzip",
  )
end

# The answer for an entry: the `.gz` bytes for a client that takes gzip and asks for the whole file (a part of a
# compressed file is not a part of the file), else the bytes as they are.
def reply(conn: Conn, entry: Entry) -> Result[Conn]
  case entry.zipped
    some(rep) ->
      if accepts_gzip?(conn) and not Files.ranged?(conn)
        return Files.respond(conn, rep, entry.path, some(entry.zipped_body))
      end

    none -> nil
  end

  Files.respond(conn, entry.rep, entry.path, some(entry.body))
end

# Whether `Accept-Encoding` lists gzip with a quality above 0 (`gzip;q=0` refuses it).
def accepts_gzip?(conn: Conn) -> Bool
  header = Conns.request_header(conn, "accept-encoding").unwrap_or("")
  header.split(",").any? do |item| gzip_item?(item) end
end

def gzip_item?(item: String) -> Bool
  parts = item.split(";").map do |part| part.strip.downcase end
  return false if parts[0] != "gzip" and parts[0] != "x-gzip"

  not parts.drop(1).any? do |param| zero_quality?(param) end
end

def zero_quality?(param: String) -> Bool
  return false if not param.start_with?("q=")

  value = param.slice(2, param.length - 2)
  not value.empty? and value.split("").all? do |ch| ch == "0" or ch == "." end
end

# The entry of the key when the file is the one it was made from: a `stat` with the same size and time of change (none
# for a trusted entry). For a text file and a client that takes gzip (`conn`) its `.gz` path must also be as it was: a
# `.gz` that was rewritten, that came after the entry (a deploy that copies the file first) or that went away makes the
# entry stale. An edit that keeps both size and time (inside one second) is not seen, as with the `ETag`. A stale entry
# is dropped and the request goes the long way, which makes a new one.
def cached(mount: Mount, key: String, conn: Conn) -> Optional[Entry]
  return none if mount.cache_bytes == 0

  found = mount.entries.get(key)
  return none if not found.ok?

  entry = found.unwrap!
  return some(entry) if entry.trusted or (unchanged?(entry) and twin_unchanged?(entry, conn))

  drop(mount, key, entry)
  none
end

# Whether the `.gz` path is as the entry saw it, asked only when the answer could be the `.gz` file: a text file, and a
# client that takes gzip and asks for the whole file.
def twin_unchanged?(entry: Entry, conn: Conn) -> Bool
  return true if not entry.rep.vary or not accepts_gzip?(conn) or Files.ranged?(conn)

  twin_stamp(entry.path) == entry.twin
end

# Removes the entry and gives its bytes back, once: of the tasks that find it stale at the same time, only the
# one whose
# claim is the first does it.
def drop(mount: Mount, key: String, entry: Entry) -> Void
  if mount.used.add("#{GONE}#{entry.id}", 1) == 1
    mount.entries.delete(key)
    _ = mount.used.add(USED, 0 - entry.cost)
  end
end

def unchanged?(entry: Entry) -> Bool
  info = File.stat(entry.path)
  return false if not info.ok? or info.unwrap!.kind != "file"

  info.unwrap!.size_bytes == entry.size and info.unwrap!.modified_seconds == entry.modified
end

# Keeps the entry unless it is over half the budget. When the bytes would pass the budget the cache is emptied first:
# no order of eviction to keep, and a file that is asked for again is read again once. The count is approximate under
# concurrent misses (a replaced entry is counted twice until the next emptying, and a task that empties may lose the
# count of another), which errs towards emptying early, and the memory stays within the budget plus the entries that
# were added at that moment.
def remember(mount: Mount, key: String, entry: Entry) -> Void
  return if entry.cost > mount.cache_bytes / 2

  total = mount.used.add(USED, entry.cost)
  if total > mount.cache_bytes
    for stale in mount.entries.keys
      mount.entries.delete(stale)
    end

    for claim in mount.used.keys
      if claim.start_with?(GONE)
        mount.used.delete(claim)
      end
    end

    mount.used.put(USED, entry.cost)
  end

  mount.entries.put(key, entry)
end

# With `fingerprint` on, the app says that a name with a fingerprint never changes its content, so it is cached for as
# long as allowed and never asked for again. The others are cached for the `max_age` of the mount: 0 asks the server
# each time, which is a cheap 304 now.
def cache_control(mount: Mount, name: String) -> String
  return "public, max-age=#{Files.MAX_AGE_SECONDS}, immutable" if mount.fingerprint and fingerprinted?(name)

  return "no-cache" if mount.max_age == 0

  "public, max-age=#{mount.max_age}"
end

# `app.3f9a1c2b.css`, `app-3f9a1c2b.css` and `main.3f9a1c2b.chunk.js`: a part of 8 to 64 lowercase hex digits between
# the first part of the name and the extension, with at least one letter and one digit, so a date (`20240131`) or a
# Unix time (`1712345678`) is not a fingerprint, nor a word (`deadbeef`). A name with no extension has none.
def fingerprinted?(name: String) -> Bool
  parts = name.replace("-", ".").split(".")
  return false if parts.size < 3

  parts.drop(1).take(parts.size - 2).any? do |part| hex_digest?(part) end
end

def hex_digest?(part: String) -> Bool
  return false if part.length < FINGERPRINT_MIN or part.length > FINGERPRINT_MAX

  chars = part.split("")
  hex = chars.all? do |ch| DIGITS.include?(ch) or LETTERS.include?(ch) end
  digit = chars.any? do |ch| DIGITS.include?(ch) end
  letter = chars.any? do |ch| LETTERS.include?(ch) end
  hex and digit and letter
end
