## Answering with a file: `send_file` gives its bytes with the `Content-Length` of the size, the validators of the
## file (`ETag`, `Last-Modified`) and the part that a `Range` header asks for. A file that fits in one piece is read
## in one call and answered as a plain body; a bigger one is read and sent in pieces by a task. `Bond.static` answers
## through the same `respond`.

import HTTP from "std/http"
import MIME from "std/mime"
import URI from "std/uri"
import Conns from "conn"
import Dates from "dates"
import {Conn} from "conn"

## The range of `piece_bytes`: 4 KiB, below which every piece costs more than the bytes it carries, and 16 MiB, above
## which a slow client holds a lot of memory for one answer (the queue holds a few pieces). The default, 64 KiB, is a
## literal in `send_file`, `Rep` and `Bond.static` (a default must be one): keep them in sync.
export MIN_PIECE_BYTES = 4_096
export MAX_PIECE_BYTES = 16_777_216

## The longest `max_age` that a cache is told to keep a file, one year in seconds (RFC 9111 section 1.2.2).
export MAX_AGE_SECONDS = 31_536_000

# The bytes before the part that a range starts at are read and dropped: `File` has no seek. A read is at most 1 MiB.
SKIP_BYTES = 1_048_576

# The most that one call of `File.read_bytes` gives.
READ_BYTES = 1_048_576

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

## What an answer says about the bytes it sends: the headers that come from the file and the policy, and the size.
## `type` is the whole `Content-Type`. `size` is that of the bytes sent (of the compressed file when `encoding` is
## `gzip`), and `modified` the Unix seconds of the last change, with `last_modified` as the header says it.
## `cache_control` and `encoding` are not sent when empty, `Vary: Accept-Encoding` is sent when `vary` is on, and a
## file of at most `piece_bytes` is answered whole.
export struct Rep
  type: String
  etag: String
  modified: Int
  last_modified: String
  size: Int
  cache_control: String = ""
  encoding: String = ""
  vary: Bool = false
  attachment: Optional[String] = none
  piece_bytes: Int = 65_536
end

# What the producer task owns: the file, the channel of the body and the part to send. Both handles close when the task
# ends, whether it returns or crashes, and the closing of the channel is the end of the body.
struct Job
  file: FileHandle
  body: Channel[Bytes]
  skip: Int
  length: Int
  piece_bytes: Int
end

## Answers with the file at `path`: its type from `std/mime` (a text type with `; charset=utf-8`), `Content-Length`,
## `ETag` and `Last-Modified` (the size and the time of the last change, with no read of the file),
## `Accept-Ranges: bytes` and `X-Content-Type-Options: nosniff`. `some(name)` as the `attachment` adds
## `Content-Disposition: attachment` with that file name (`some("")` has no name).
##
## A `GET` or `HEAD` that has `If-None-Match` with the tag, or has no `If-None-Match` and an `If-Modified-Since` that is
## not before the change, is a 304 with no body. `max_age` is the `Cache-Control`: `some(0)` is `no-cache`, and
## `some(n)` is `private, max-age=n` (0 to a year; `private` since a file sent by a route is often for one person), or
## `public, max-age=n` with `public: true`, which lets a shared cache (a proxy, a CDN) keep it for everyone.
## With `none`, a `Cache-Control` that the conn already has is kept, and otherwise it is `no-cache`: a cache asks again
## each time, a cheap 304, as it did before the answer had a validator.
##
## A file of at most `piece_bytes` (4 KiB to 16 MiB, 64 KiB by default) is read in one call, and a bigger one is read
## in pieces of that size by a task that the call starts, so the memory does not grow with the size.
## A `Range` header of one range (`bytes=0-99`, `bytes=100-`, `bytes=-500`) is answered with a 206 and `Content-Range`,
## and a range that starts beyond the end with a 416 and `Content-Range: bytes */size`. A range with several parts, a
## bad one, and any `Range` when the request has `If-Range` (the validator of a file is not strong enough to compare
## it with) are ignored: the whole file is the answer. A `HEAD` request gets the headers with the length and no body.
## An `error` is a file that is not a plain file or that cannot be opened, or a `max_age` or `piece_bytes` out of range.
##
## The status is always set: 200, 206, 304 or 416, whatever it was before. So a custom `not_found` page that sends a
## file answers 200 unless `Bond.status` comes after, and a client that sends a `Range` to such a page can get a 206.
export def send_file(
  conn: Conn,
  path: String,
  attachment: Optional[String] = none,
  max_age: Optional[Int] = none,
  public: Bool = false,
  piece_bytes: Int = 65_536,
) -> Result[Conn]
  if piece_bytes < MIN_PIECE_BYTES or piece_bytes > MAX_PIECE_BYTES
    return error("piece_bytes must be #{MIN_PIECE_BYTES} to #{MAX_PIECE_BYTES}, not #{piece_bytes}")
  end

  cache = ""
  case max_age
    some(seconds) ->
      if seconds < 0 or seconds > MAX_AGE_SECONDS
        return error("max_age must be 0 to #{MAX_AGE_SECONDS}, not #{seconds}")
      end

      cache = max_age_text(seconds, public)
    none -> cache = default_cache_control(conn)
  end

  info = File.stat(path)
  return error("the file #{file_name(path)} cannot be read") if not info.ok? or info.unwrap!.kind != "file"

  rep = describe(file_name(path), attachment, info.unwrap!, cache).with(piece_bytes: piece_bytes)
  respond(conn, rep, path, none)
end

## The `Rep` of the file with the `info` of `stat`, typed by `type_name` (a file name or an extension).
export def describe(type_name: String, attachment: Optional[String], info: FileInfo, cache: String) -> Rep
  type = MIME.mime_type(type_name)
  label = type
  if MIME.text?(type)
    label = "#{type}; charset=utf-8"
  end

  Rep(
    type: label,
    etag: etag_of(info),
    modified: info.modified_seconds,
    last_modified: Dates.format(info.modified_seconds),
    size: info.size_bytes,
    cache_control: cache,
    attachment: attachment,
  )
end

## Whether the request asks for a part of the file, which a compressed answer cannot give.
export def ranged?(conn: Conn) -> Bool = not request_range(conn).empty?

## Answers with the bytes described by `rep`: a 304 for a conditional request that the validators satisfy, else a 200,
## 206 or 416 for the range. The bytes are `loaded` when the caller has them, else the file at `path` (the one that
## `rep` describes, for `Rep.size` bytes), read whole when it fits in one piece and in pieces when it does not.
export def respond(conn: Conn, rep: Rep, path: String, loaded: Optional[Bytes]) -> Result[Conn]
  Conns.close_stream(conn)
  bare = conn.with(response_stream: none, response_length: none)
  if (conn.method == "GET" or conn.method == "HEAD") and not_modified?(bare, rep)
    return ok(validated(bare, rep).with(status: 304, response_body: "".bytes))
  end

  slice = slice_of(request_range(bare), rep.size)
  typed = headed(bare, rep, slice)
  return ok(typed.with(status: slice.status, response_body: "".bytes)) if slice.status == 416 or slice.size == 0

  if conn.method == "HEAD"
    # The server closes the channel of a HEAD answer, so no producer is needed to read a file nobody asked for.
    return ok(Conns.stream(typed, slice.status, Channel.new(1), some(slice.size)))
  end

  case loaded
    some(body) -> return ok(whole(typed, slice, body))
    none -> nil
  end

  if rep.size <= rep.piece_bytes
    body = try read_whole(path, rep.size)
    return ok(whole(typed, slice, body))
  end

  file = File.open(path, "read", READ_MS)
  return error("the file #{file_name(path)} cannot be read") if not file.ok?

  body: Channel[Bytes] = Channel.new(QUEUE_PIECES)
  job = Job(file: file.unwrap!, body: body, skip: slice.first, length: slice.size, piece_bytes: rep.piece_bytes)
  Task.spawn_owning(&pump, job)
  ok(Conns.stream(typed, slice.status, body, some(slice.size)))
end

## The bytes of the file at `path`, which has `size` bytes, read in one go.
export def read_whole(path: String, size: Int) -> Result[Bytes]
  return ok("".bytes) if size == 0

  file = try File.open(path, "read", READ_MS)
  read = read_up_to(file, size)
  _ = File.close(file, READ_MS)
  return error("the file #{file_name(path)} cannot be read") if not read.ok? or read.unwrap!.size != size

  read
end

# A strong validator from what `stat` gives, with no read of the file: the size and the time of the last change in
# seconds. An edit that keeps the size and happens in the same second as the last one is not seen.
def etag_of(info: FileInfo) -> String = "\"#{info.size_bytes.to_s}-#{info.modified_seconds.to_s}\""

# The `Cache-Control` of `max_age` seconds: for one person's cache unless `public`.
def max_age_text(seconds: Int, public: Bool) -> String
  return "no-cache" if seconds == 0

  return "public, max-age=#{seconds}" if public

  "private, max-age=#{seconds}"
end

def default_cache_control(conn: Conn) -> String
  return "" if conn.response_headers.any? do |header| header.name.downcase == "cache-control" end

  "no-cache"
end

# The answer with the part of the bytes that `slice` names, as a plain body. `response_length` is not needed by the
# server, which counts the body, but `Testing.request` shows it as the `Content-Length` of the answer.
def whole(typed: Conn, slice: Slice, body: Bytes) -> Conn
  part = body
  if slice.status == 206
    part = body.slice(slice.first, slice.size)
  end

  typed.with(status: slice.status, response_body: part, response_length: some(slice.size))
end

# Whether the validators of the request say that the client has the bytes: `If-None-Match` when there is one, else
# `If-Modified-Since` (RFC 9110 section 13.2.2). A date that is not in the form of `Dates.parse` is ignored.
def not_modified?(conn: Conn, rep: Rep) -> Bool
  tags = Conns.request_header(conn, "if-none-match")
  return matches?(tags.unwrap!, rep.etag) if tags.ok?

  since = Conns.request_header(conn, "if-modified-since")
  return false if not since.ok?

  case Dates.parse(since.unwrap!)
    some(seconds) -> rep.modified <= seconds
    none -> false
  end
end

# Whether `If-None-Match` lists the tag (or is `*`). The comparison is the weak one that this header uses (RFC 9110
# section 13.1.2): a leading `W/` is dropped from the tag of the request. A tag with a comma inside is not told apart,
# which the tags of Bond never have.
def matches?(header: String, etag: String) -> Bool
  header.split(",").any? do |item|
    tag = item.strip
    if tag.start_with?("W/")
      tag = tag.slice(2, tag.length - 2)
    end

    tag == "*" or tag == etag
  end
end

# The headers of a 304, and of every answer: the validators, the cache policy and `Vary`.
def validated(conn: Conn, rep: Rep) -> Conn = Conns.set_headers(conn, validators(rep))

def validators(rep: Rep) -> List[HTTP.Header]
  fields = [HTTP.Header(name: "etag", value: rep.etag), HTTP.Header(name: "last-modified", value: rep.last_modified)]
  if not rep.cache_control.empty?
    fields = fields.push(HTTP.Header(name: "cache-control", value: rep.cache_control))
  end

  if rep.vary
    fields = fields.push(HTTP.Header(name: "vary", value: "Accept-Encoding"))
  end

  fields
end

# The part of a file of `size` bytes that the value of a `Range` header asks for ("" when there is none).
def slice_of(value: String, size: Int) -> Slice
  all = Slice(status: 200, first: 0, size: size)
  spec = value.strip
  return all if not spec.downcase.start_with?("bytes=")

  list = spec.slice(6, spec.length - 6).strip
  return all if list.include?(",") or list.empty?

  case list.index_of("-")
    none -> all
    some(at) ->
      left = list.slice(0, at).strip
      right = list.slice(at + 1, list.length - at - 1).strip
      choose(left, right, size, all)
  end
end

# `left-right`, `left-` or `-right` of a range with the digits already split. A range that is not made of digits, or
# that ends before it starts, is not a range, so the answer is the whole file.
def choose(left: String, right: String, size: Int, all: Slice) -> Slice
  if left.empty? and digits?(right)
    count = number(right)
    return Slice(status: 416, first: 0, size: 0) if count == 0 or size == 0

    first = size - smaller(count, size)
    return Slice(status: 206, first: first, size: size - first)
  end

  return all if not digits?(left) or not (right.empty? or digits?(right))

  first = number(left)
  last = HUGE
  if not right.empty?
    last = number(right)
  end

  return all if last < first

  return Slice(status: 416, first: 0, size: 0) if first >= size

  end_at = smaller(last, size - 1)
  Slice(status: 206, first: first, size: end_at - first + 1)
end

def digits?(text: String) -> Bool = not text.empty? and text.split("").all? do |ch| ch.code >= 48 and ch.code <= 57 end

def number(text: String) -> Int
  return HUGE if text.length > MAX_DIGITS

  text.to_i!
end

def smaller(a: Int, b: Int) -> Int
  return a if a < b

  b
end

# The `Range` of the request, or "" when it has none or has `If-Range`.
def request_range(conn: Conn) -> String
  return "" if Conns.request_header(conn, "if-range").ok?

  Conns.request_header(conn, "range").unwrap_or("")
end

# The headers of the answer, for any `slice`: the validators, the type, the ranges, the `Content-Range` of a part, the
# encoding, and the disposition. They are set in one call, in this order.
def headed(conn: Conn, rep: Rep, slice: Slice) -> Conn
  fields = validators(rep)
  fields = fields.push(HTTP.Header(name: "content-type", value: rep.type))
  fields = fields.push(HTTP.Header(name: "x-content-type-options", value: "nosniff"))
  fields = fields.push(HTTP.Header(name: "accept-ranges", value: "bytes"))
  case rep.attachment
    some(name) -> fields = fields.push(HTTP.Header(name: "content-disposition", value: disposition(name)))
    none -> nil
  end

  if not rep.encoding.empty?
    fields = fields.push(HTTP.Header(name: "content-encoding", value: rep.encoding))
  end

  if slice.status == 206
    last = slice.first + slice.size - 1
    fields = fields.push(HTTP.Header(name: "content-range", value: "bytes #{slice.first}-#{last}/#{rep.size}"))
  end

  if slice.status == 416
    fields = fields.push(HTTP.Header(name: "content-range", value: "bytes */#{rep.size}"))
  end

  Conns.set_headers(conn, fields)
end

# The value of `Content-Disposition` for a download with the name `name`: a quoted `filename` of the printable ASCII of
# the name (anything else is `_`), and the exact name as `filename*` (RFC 6266) when they differ.
def disposition(name: String) -> String
  return "attachment" if name.empty?

  chars = name.split("").map do |ch| fallback_char(ch) end
  plain = chars.join("")
  return "attachment; filename=\"#{plain}\"" if plain == name

  "attachment; filename=\"#{plain}\"; filename*=UTF-8''#{URI.encode_uri_component(name)}"
end

def fallback_char(ch: String) -> String
  return "_" if ch.code < 32 or ch.code > 126 or ch == "\"" or ch == "\\"

  ch
end

# The last segment of a path, with either kind of separator.
def file_name(path: String) -> String = path.replace("\\", "/").split("/").last

# Runs as the owner of the job. It ends early, with the channel closed, when the file is shorter than it was when the
# answer was made, when a read fails or when the client is gone, and the server cuts the body: it never reads past the
# length it announced.
def pump(job: Job) -> Void
  return if not skip_bytes(job.file, job.skip)

  left = job.length
  while left > 0
    case read_up_to(job.file, smaller(job.piece_bytes, left))
      error(_) -> return
      ok(piece) ->
        return if piece.empty? or not job.body.send(piece, SEND_MS).ok?

        left = left - piece.size
    end
  end
end

# `count` bytes (at least 1), or fewer at the end of the file, as one `Bytes`: a piece can be bigger than the 1
# MiB that
# one read gives.
def read_up_to(file: FileHandle, count: Int) -> Result[Bytes]
  got = try File.read_bytes(file, smaller(READ_BYTES, count), READ_MS)
  while not got.empty? and got.size < count
    more = try File.read_bytes(file, smaller(READ_BYTES, count - got.size), READ_MS)
    break if more.empty?

    got = got + more
  end

  ok(got)
end

def skip_bytes(file: FileHandle, count: Int) -> Bool
  left = count
  while left > 0
    piece = File.read_bytes(file, smaller(SKIP_BYTES, left), READ_MS)
    return false if not piece.ok? or piece.unwrap!.empty?

    left = left - piece.unwrap!.size
  end

  true
end
