## Static files: a folder served under a path, read with `File` and typed with `std/mime`.

import MIME from "std/mime"
import URI from "std/uri"
import Conns from "conn"
import Pattern from "pattern"
import {Conn} from "conn"

## The largest `max_bytes`: `File.read_text` reads a file of 1 MiB at most.
export MAX_FILE_BYTES = 1_048_576

## The files of the folder `root` are served under the path `prefix`; a file over `max_bytes` is not served.
export struct Mount
  prefix: String
  root: String
  max_bytes: Int
end

## The answer of the first mount that holds the path of the request: a file (200), a 405 for a method other than GET
## and HEAD, or a 500 for a file that cannot be sent. An `error` means that the request is not for a file (nothing
## of that name, a folder, a way out of the folder), so the caller answers it as a path with no route.
export def serve(mounts: List[Mount], conn: Conn) -> Result[Conn]
  for mount in mounts
    inside = below(mount, conn.path)
    if inside.ok?
      return answer(mount, inside.unwrap!, conn)
    end
  end

  return error("no static folder for the path")
end

# The segments of the path after the prefix of the mount, as the client sent them (not decoded), when there is at least
# one. Prefix and path are compared segment by segment, so /assetsx is not under /assets.
def below(mount: Mount, path: String) -> Result[List[String]]
  wanted = Pattern.segments(mount.prefix)
  found = Pattern.segments(path)
  if found.size <= wanted.size
    return error("not under the prefix")
  end

  for i in 0...wanted.size
    if wanted[i] != found[i]
      return error("not under the prefix")
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
  return ok(send(mount, conn, file, names.last))
end

# Each segment is decoded, and then refused when it could leave the folder or name something that is not a plain file
# of it: an empty name, a name that starts with a dot (`..` and the files that are hidden), a slash, a backslash, a
# colon (a drive of Windows) or a control character (NUL included). So `%2e%2e`, `%2F` and `%5C` are refused too.
def decode(parts: List[String]) -> Result[List[String]]
  names: List[String] = []
  for part in parts
    decoded = try URI.decode_uri_component(part)
    if decoded.empty? or decoded.start_with?(".") or decoded.split("").any? do |ch| unsafe?(ch) end
      return error("not a name of a file")
    end

    names = names.push(decoded)
  end

  return ok(names)
end

def unsafe?(ch: String) -> Bool
  code = ch.code
  return code < 32 or code == 127 or ch == "/" or ch == "\\" or ch == ":"
end

# The real path of the file, with the links followed, when it is a file inside the real folder. A link that leads
# out of the folder is refused. The file can still change between this check and the read.
def locate(mount: Mount, names: List[String]) -> Result[String]
  root = try Path.real(mount.root)
  joined = try Path.join(List.concat([mount.root], names))
  file = try Path.real(joined)
  if not file.start_with?(with_separator(root))
    return error("outside the folder")
  end

  info = try File.stat(file)
  if info.kind != "file"
    return error("not a file")
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

# A file that is too big, or is not UTF-8 text, cannot be a body: a 500, with the reason on stderr.
def send(mount: Mount, conn: Conn, file: String, name: String) -> Conn
  case read(mount, file, name)
    ok(text) -> return typed(conn, name, text)
    error(reason) -> return failed(conn, reason)
  end
end

def read(mount: Mount, file: String, name: String) -> Result[String]
  info = try File.stat(file)
  if info.size_bytes > mount.max_bytes
    return error("#{name} is over #{mount.max_bytes} bytes")
  end

  return File.read_text(file)
end

def typed(conn: Conn, name: String, text: String) -> Conn
  type = MIME.mime_type(name)
  if MIME.text?(type)
    type = "#{type}; charset=utf-8"
  end

  return Conns.header(Conns.header(conn, "content-type", type), "x-content-type-options", "nosniff").with(
    status: 200,
    response_body: text,
  )
end

def failed(conn: Conn, reason: String) -> Conn
  IO.warn("bond: #{conn.method} #{conn.path}: static file: #{reason}")
  return Conns.halt(conn, 500, Conns.INTERNAL_ERROR)
end
