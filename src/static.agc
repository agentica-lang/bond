## Static files: a folder served under a path, read with `File` and typed with `std/mime`.

import MIME from "std/mime"
import URI from "std/uri"
import Conns from "conn"
import Pattern from "pattern"
import {Conn} from "conn"

## The largest `max_bytes`: `File.read_text` reads a file of 1 MiB at most.
export MAX_FILE_BYTES = 1_048_576

## The reason of the `error` of `serve` for a request that is not for a file. Any other `error` is a failure.
export MISS = "not a static file"

# `File.read_text` waits on a FIFO that no one writes to, so the wait is short.
READ_MS = 5_000

# Names that Windows opens as a device, whatever the extension and the case.
DEVICES = Set.new([
  "CON", "PRN", "AUX", "NUL",
  "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
  "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
])

BINARY_NOTICE = (
  "bond: a static file is not text, and a binary file needs a body of bytes in std/http (Agentica #805, #803)"
)

## The files of the folder `root` (a real path) are served under the path `prefix`; a file over `max_bytes` is not
## served.
export struct Mount
  prefix: String
  root: String
  max_bytes: Int
end

## The real path of the folder of a mount, when it is a folder. It is read once, when the app is built.
export def real_root(root: String) -> Result[String]
  info = try File.stat(root)
  if info.kind != "directory"
    return error("not a folder")
  end

  return Path.real(root)
end

## The answer of the first mount that holds the path of the request: a file (200), a 405 for a method other than GET
## and HEAD, or a 501 for a file that is not text. An `error` with the reason `MISS` means that the request is not
## for a file (nothing of that name, a folder, a hidden name, a way out of the folder), so the caller answers it as a
## path with no route. Any other `error` is a file that cannot be sent (too big, not UTF-8), for the error handler.
## `notes` remembers what was said on stderr, so that the notice about binary files is written once.
export def serve(mounts: List[Mount], notes: ATS[String, Bool], conn: Conn) -> Result[Conn]
  for mount in mounts
    inside = below(mount, conn.path)
    if inside.ok?
      return answer(mount, notes, inside.unwrap!, conn)
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

def answer(mount: Mount, notes: ATS[String, Bool], parts: List[String], conn: Conn) -> Result[Conn]
  if conn.method != "GET" and conn.method != "HEAD"
    return ok(Conns.halt(Conns.header(conn, "allow", "GET, HEAD"), 405, "method not allowed"))
  end

  names = try decode(parts)
  file = try locate(mount, names)
  name = names.last
  type = MIME.mime_type(name)
  # The type decides before the file is read: a body is text, so a file that is not text cannot be sent.
  if not MIME.text?(type)
    return ok(not_implemented(notes, conn))
  end

  text = try read(mount, file, name)
  return ok(typed(conn, type, text))
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

# The reasons are for stderr and the error handler, in words: the text of a failed read is the VM's, not ours.
def read(mount: Mount, file: String, name: String) -> Result[String]
  info = File.stat(file)
  if not info.ok?
    return error("the static file #{name} cannot be read")
  end

  if info.unwrap!.size_bytes > mount.max_bytes
    return error("the static file #{name} is over #{mount.max_bytes} bytes")
  end

  text = File.read_text(file, READ_MS)
  if not text.ok?
    return error("the static file #{name} is not valid UTF-8 text or could not be read")
  end

  return text
end

# A 501 with a fixed body; the notice goes to stderr once, since a site that links to images would fill the log.
def not_implemented(notes: ATS[String, Bool], conn: Conn) -> Conn
  if ATS.put_new(notes, "binary", true)
    IO.warn(BINARY_NOTICE)
  end

  return Conns.halt(conn, 501, "Not Implemented")
end

def typed(conn: Conn, type: String, text: String) -> Conn
  typed_conn = Conns.header(conn, "content-type", "#{type}; charset=utf-8")
  return Conns.header(typed_conn, "x-content-type-options", "nosniff").with(status: 200, response_body: text)
end
