## Static files: a folder served under a path, sent by `Files.send` (read in pieces, typed with `std/mime`).

import URI from "std/uri"
import Conns from "conn"
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

## The longest `max_age`, one year in seconds: the longest that a cache is told to keep a file (RFC 9111 section 1.2.2),
## and what a fingerprinted file gets when `fingerprint` is on.
export MAX_AGE_SECONDS = 31_536_000

DIGITS = Set.new(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
LETTERS = Set.new(["a", "b", "c", "d", "e", "f"])

# The length of the digest in a fingerprinted name: 8 hex digits (a short hash) to 64 (a SHA-256).
FINGERPRINT_MIN = 8
FINGERPRINT_MAX = 64

## The files of the folder `root` (a real path) are served under the path `prefix`; a file over `max_bytes` is not
## served. `max_age` is the seconds that a cache may keep a file (0 is "ask each time"). With `fingerprint`, a name that
## has a fingerprint is kept for a year, whatever `max_age` is.
export struct Mount
  prefix: String
  root: String
  max_bytes: Int
  max_age: Int = 0
  fingerprint: Bool = false
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

  names = try decode(parts)
  file = try locate(mount, names)
  name = names.last
  return send(mount, file, name, conn)
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
def locate(mount: Mount, names: List[String]) -> Result[String]
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

  return ok(file)
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

# The reasons are for stderr and the error handler, in words: the text of a failed read is the VM's, not ours. The size
# is checked here and the file is sent by `Files.send`, which reads it in pieces, so a big file costs no memory.
def send(mount: Mount, file: String, name: String, conn: Conn) -> Result[Conn]
  info = File.stat(file)
  if not info.ok?
    return error("the static file #{name} cannot be read")
  end

  size = info.unwrap!.size_bytes
  if size > mount.max_bytes
    return error("the static file #{name} is over #{mount.max_bytes} bytes")
  end

  etag = etag_of(info.unwrap!)
  cache = cache_control(mount, name)
  if matches?(conn, etag)
    return ok(
      Conns.header(
        Conns.header(conn.with(status: 304, response_body: "".bytes), "etag", etag),
        "cache-control",
        cache,
      ),
    )
  end

  sent = Files.send(conn, file, name)
  if not sent.ok?
    return error("the static file #{name} cannot be read")
  end

  return ok(Conns.header(Conns.header(sent.unwrap!, "etag", etag), "cache-control", cache))
end

# A strong validator from what `stat` gives, with no read of the file: the size and the time of the last change in
# seconds. An edit that keeps the size and happens in the same second as the last one is not seen.
def etag_of(info: FileInfo) -> String
  return "\"#{info.size_bytes.to_s}-#{info.modified_seconds.to_s}\""
end

# Whether `If-None-Match` lists the tag (or is `*`). The comparison is the weak one that this header uses (RFC 9110
# section 13.1.2): a leading `W/` is dropped from the tag of the request. A tag with a comma inside is not told apart,
# which the tags of Bond never have.
def matches?(conn: Conn, etag: String) -> Bool
  header = Conns.request_header(conn, "if-none-match").unwrap_or("")
  return header.split(",").any? do |item|
    tag = item.strip
    if tag.start_with?("W/")
      tag = tag.slice(2, tag.length - 2)
    end

    tag == "*" or tag == etag
  end
end

# With `fingerprint` on, the app says that a name with a fingerprint never changes its content, so it is cached for as
# long as allowed and never asked for again. The others are cached for the `max_age` of the mount: 0 asks the server
# each time, which is a cheap 304 now.
def cache_control(mount: Mount, name: String) -> String
  if mount.fingerprint and fingerprinted?(name)
    return "public, max-age=#{MAX_AGE_SECONDS}, immutable"
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
