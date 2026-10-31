## Answering with a file: `send_file` gives its bytes in pieces with the `Content-Length` of the size, and the part
## that a `Range` header asks for. `Bond.static` answers through the same function.

import MIME from "std/mime"
import URI from "std/uri"
import Conns from "conn"
import {Conn} from "conn"

# The size of the pieces that are read from the file and sent.
PIECE_BYTES = 65_536

# The bytes before the part that a range starts at are read and dropped: `File` has no seek. A read is at most 1 MiB.
SKIP_BYTES = 1_048_576

# One read waits on a file that blocks (a FIFO that no one writes to), so the wait is short.
READ_MS = 5_000

# One send waits for the client to take a piece. A client that stops reading for this long loses the download.
SEND_MS = 60_000

# The pieces that wait in the channel, so the file is read ahead a little and the memory is bounded.
QUEUE_PIECES = 4

# A number of digits too long for an `Int` is this: beyond the end of any file.
HUGE = 1_000_000_000_000_000_000

# The most digits of a number that is converted as it is.
MAX_DIGITS = 18

# Which bytes of the file the request wants: `status` is 200 (all of it), 206 (the `size` bytes from `first`) or 416
# (the range starts beyond the end of the file).
struct Slice
  status: Int
  first: Int
  size: Int
end

# What the producer task owns: the file, the channel of the body and the part to send. Both handles close when the task
# ends, whether it returns or crashes, and the closing of the channel is the end of the body.
struct Job
  file: FileHandle
  body: Channel[Bytes]
  skip: Int
  length: Int
end

## Answers with the file at `path`: its type from `std/mime` (a text type with `; charset=utf-8`), `Content-Length`,
## `Accept-Ranges: bytes` and `X-Content-Type-Options: nosniff`. `some(name)` as the `attachment` adds
## `Content-Disposition: attachment` with that file name (`some("")` has no name).
##
## The status is always set: 200, or 206 and 416 for a `Range` header, whatever it was before. So a custom
## `not_found` page that sends a file answers 200 unless `Bond.status` comes after, and a client that sends a `Range`
## to such a page can get a 206. See `send` for the rules of the range and the body.
export def send_file(conn: Conn, path: String, attachment: Optional[String] = none) -> Result[Conn]
  return send(conn, path, file_name(path), attachment)
end

## `send_file` for a file whose type comes from `type_name` (a file name or an extension), not from `path`.
## A `Range` header of one range (`bytes=0-99`, `bytes=100-`, `bytes=-500`) is answered with a 206 and
## `Content-Range`, and a range that starts beyond the end with a 416 and `Content-Range: bytes */size`. A range with
## several parts, a bad one, and any `Range` when the request has `If-Range` (Bond keeps no validator to compare it
## with) are ignored: the whole file is the answer. The file is read in pieces by a task that the call starts, so the
## memory does not grow with the size, and a `HEAD` request gets the headers with the length and no body. An
## `error` is a file that is not a plain file or that cannot be opened.
export def send(conn: Conn, path: String, type_name: String, attachment: Optional[String] = none) -> Result[Conn]
  info = File.stat(path)
  if not info.ok? or info.unwrap!.kind != "file"
    return error("the file #{file_name(path)} cannot be read")
  end

  size = info.unwrap!.size_bytes
  slice = slice_of(request_range(conn), size)
  typed = headed(conn, type_name, attachment, slice, size)
  Conns.close_stream(typed)
  bare = typed.with(response_stream: none, response_length: none)
  if slice.status == 416 or slice.size == 0
    return ok(bare.with(status: slice.status, response_body: "".bytes))
  end

  if conn.method == "HEAD"
    # The server closes the channel of a HEAD answer, so no producer is needed to read a file nobody asked for.
    return ok(Conns.stream(bare, slice.status, Channel.new(1), some(slice.size)))
  end

  file = File.open(path, "read", READ_MS)
  if not file.ok?
    return error("the file #{file_name(path)} cannot be read")
  end

  body: Channel[Bytes] = Channel.new(QUEUE_PIECES)
  Task.spawn_owning(&pump, Job(file: file.unwrap!, body: body, skip: slice.first, length: slice.size))
  return ok(Conns.stream(bare, slice.status, body, some(slice.size)))
end

# The part of a file of `size` bytes that the value of a `Range` header asks for ("" when there is none).
def slice_of(value: String, size: Int) -> Slice
  all = Slice(status: 200, first: 0, size: size)
  spec = value.strip
  if not spec.downcase.start_with?("bytes=")
    return all
  end

  list = spec.slice(6, spec.length - 6).strip
  if list.include?(",") or list.empty?
    return all
  end

  case list.index_of("-")
    none -> return all
    some(at) ->
      left = list.slice(0, at).strip
      right = list.slice(at + 1, list.length - at - 1).strip
      return choose(left, right, size, all)
  end
end

# `left-right`, `left-` or `-right` of a range with the digits already split. A range that is not made of digits, or
# that ends before it starts, is not a range, so the answer is the whole file.
def choose(left: String, right: String, size: Int, all: Slice) -> Slice
  if left.empty? and digits?(right)
    count = number(right)
    if count == 0 or size == 0
      return Slice(status: 416, first: 0, size: 0)
    end

    first = size - smaller(count, size)
    return Slice(status: 206, first: first, size: size - first)
  end

  if not digits?(left) or not (right.empty? or digits?(right))
    return all
  end

  first = number(left)
  last = HUGE
  if not right.empty?
    last = number(right)
  end

  if last < first
    return all
  end

  if first >= size
    return Slice(status: 416, first: 0, size: 0)
  end

  end_at = smaller(last, size - 1)
  return Slice(status: 206, first: first, size: end_at - first + 1)
end

def digits?(text: String) -> Bool
  return not text.empty? and text.split("").all? do |ch| ch.code >= 48 and ch.code <= 57 end
end

def number(text: String) -> Int
  if text.length > MAX_DIGITS
    return HUGE
  end

  return text.to_i!
end

def smaller(a: Int, b: Int) -> Int
  if a < b
    return a
  end

  return b
end

# The `Range` of the request, or "" when it has none or has `If-Range`.
def request_range(conn: Conn) -> String
  if Conns.request_header(conn, "if-range").ok?
    return ""
  end

  return Conns.request_header(conn, "range").unwrap_or("")
end

# The headers of the answer, for any `slice`: the type, the ranges, the `Content-Range` of a part, and the disposition.
def headed(conn: Conn, type_name: String, attachment: Optional[String], slice: Slice, size: Int) -> Conn
  type = MIME.mime_type(type_name)
  label = type
  if MIME.text?(type)
    label = "#{type}; charset=utf-8"
  end

  typed = Conns.header(Conns.header(conn, "content-type", label), "x-content-type-options", "nosniff")
  ranged = Conns.header(typed, "accept-ranges", "bytes")
  named = ranged
  case attachment
    some(name) -> named = Conns.header(ranged, "content-disposition", disposition(name))
    none -> named = ranged
  end

  if slice.status == 206
    last = slice.first + slice.size - 1
    return Conns.header(named, "content-range", "bytes #{slice.first}-#{last}/#{size}")
  end

  if slice.status == 416
    return Conns.header(named, "content-range", "bytes */#{size}")
  end

  return named
end

# The value of `Content-Disposition` for a download with the name `name`: a quoted `filename` of the printable ASCII of
# the name (anything else is `_`), and the exact name as `filename*` (RFC 6266) when they differ.
def disposition(name: String) -> String
  if name.empty?
    return "attachment"
  end

  plain = name.split("").map do |ch| fallback_char(ch) end.join("")
  if plain == name
    return "attachment; filename=\"#{plain}\""
  end

  return "attachment; filename=\"#{plain}\"; filename*=UTF-8''#{URI.encode_uri_component(name)}"
end

def fallback_char(ch: String) -> String
  if ch.code < 32 or ch.code > 126 or ch == "\"" or ch == "\\"
    return "_"
  end

  return ch
end

# The last segment of a path, with either kind of separator.
def file_name(path: String) -> String
  return path.replace("\\", "/").split("/").last
end

# Runs as the owner of the job. It ends early, with the channel closed, when the file is shorter than it was when the
# answer was made, when a read fails or when the client is gone, and the server cuts the body: it never reads past the
# length it announced.
def pump(job: Job) -> Void
  if not skip_bytes(job.file, job.skip)
    return
  end

  left = job.length
  while left > 0
    case File.read_bytes(job.file, smaller(PIECE_BYTES, left), READ_MS)
      error(_) -> return
      ok(piece) ->
        if piece.empty? or not job.body.send(piece, SEND_MS).ok?
          return
        end

        left = left - piece.size
    end
  end
end

def skip_bytes(file: FileHandle, count: Int) -> Bool
  left = count
  while left > 0
    piece = File.read_bytes(file, smaller(SKIP_BYTES, left), READ_MS)
    if not piece.ok? or piece.unwrap!.empty?
      return false
    end

    left = left - piece.unwrap!.size
  end

  return true
end
