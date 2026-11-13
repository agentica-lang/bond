## File uploads: a `multipart/form-data` body read as it arrives, its files saved to a private temporary folder with
## size caps, and its text fields kept for `Bond.form`. The body is read only for a request that reached its route,
## after the `before` filters, and the folder is removed after the answer.

import HTTP from "std/http"
import URI from "std/uri"
import Apps from "app"
import Conns from "conn"
import Multipart from "multipart"
import {App, UploadOptions} from "app"
import {Conn, Form, UploadedFile} from "conn"

## Turns on uploads: a request whose `Content-Type` is `multipart/form-data` has its body read as it arrives, once the
## `before` filters passed it and its route was found. A filter that halts (`Bond.csrf`, a login check), a path with no
## route (404) or with no route for the method (405) is answered without reading the body. Each file goes to a private
## folder made for the request under `options.dir`, under a name of Bond's own, never the client's; the text fields go
## to `Bond.form`, `form_all`, `form_int` and `form_params`; `Bond.file(conn, name)` gives a file. A file over
## `max_file_bytes`, a text field over `max_field_bytes`, all the text fields over `max_fields_bytes`, a body over
## `max_total_bytes` or more than 1000 parts is a 413 that closes the connection, and the handler does not run; a body
## that is not `multipart/form-data` as RFC 7578 frames it is a 400. The folder and every file in it are removed when
## the answer is ready (for a stream, before it is sent), so a handler that keeps a file moves it. Other requests keep
## the body limit of the server (`max_body_bytes` of `Bond.start_with`); the server takes a body up to
## `max_total_bytes` for these. Only a POST, PUT or PATCH is read this way: another method with that type keeps the
## server's limit and its body stays in `conn.body`. The program stops when a limit is below 1, when `max_file_bytes`
## is above `max_total_bytes`, when `max_field_bytes` is above `max_fields_bytes`, or when `max_total_bytes` is above
## 256 MiB.
def uploads(app: App, options: UploadOptions = UploadOptions()) -> App
  fields_ok = options.max_field_bytes >= 1 and options.max_field_bytes <= options.max_fields_bytes
  if options.max_file_bytes < 1 or options.max_file_bytes > options.max_total_bytes or not fields_ok
    bad: Result[App] = error(
      "bond: the upload limits must be 1 or more, max_file_bytes at most max_total_bytes and max_field_bytes at most " +
      "max_fields_bytes",
    )

    return bad.unwrap!
  end

  if options.max_total_bytes > SERVER_MAX_BODY
    bad: Result[App] = error("bond: max_total_bytes of uploads must be at most #{SERVER_MAX_BODY}")
    return bad.unwrap!
  end

  app.with(uploads: some(options))
end

## The first file of the field `name`, or an error that makes a 400 when there is none (so `try Bond.file(...)`
## answers it). A field that came as text is no file.
def file(conn: Conn, name: String) -> Result[UploadedFile]
  found = file_all(conn, name)
  return Conns.bad_request("file #{name} is missing") if found.empty?

  ok(found[0])
end

## Every file of the field `name`, in order (`<input type="file" multiple>`): an empty list when there is none.
def file_all(conn: Conn, name: String) -> List[UploadedFile]
  case conn.form
    some(parts) -> parts.files.select do |upload| upload.name == name end
    none -> []
  end
end

## The upload options when they apply to the request: the app has uploads, the method is one that sends a form body
## (POST, PUT, PATCH; a DELETE or a GET with a body is no upload) and the body is `multipart/form-data`.
def applies(app: App, request: HTTP.Request) -> Optional[UploadOptions]
  return none if not BODY_METHODS.any? do |method| method == request.method end

  types = HTTP.header_values(request.headers, "content-type")
  return none if types.size != 1 or types[0].split(";")[0].strip.downcase != MULTIPART_TYPE

  app.uploads
end

## The body limit of the server: the larger of the one of the other requests and the uploads' total.
def server_limit(app: App, limit: Int) -> Int
  case app.uploads
    some(options) ->
      return options.max_total_bytes if options.max_total_bytes > limit

      limit

    none -> limit
  end
end

## The answer of `HTTP.serve` for a request that `applies`: the app runs with a `Receiver` that reads the body when
## the request reaches its route, and the folder of the files is removed after.
def answer(app: App, options: UploadOptions, request: HTTP.Request, body: HTTP.RequestBody) -> HTTP.Answer
  dir = folder(options)
  answered = Apps.handle_answer_with(app, request.with(body: "".bytes)) do |_conn|
    receive(options, dir, request, body)
  end

  remove(dir)
  answered
end

## Like `answer`, for `Testing.request`: the body is given whole, in pieces of 64 KiB, and the answer is whole.
def handle(app: App, options: UploadOptions, request: HTTP.Request, max_pieces: Int, timeout_ms: Int) -> HTTP.Response
  pieces: Channel[Bytes] = Channel.new(request.body.size / TEST_PIECE + 1)
  at = 0
  while at < request.body.size
    pieces.send(request.body.drop(at).take(TEST_PIECE), 0).unwrap!
    at = at + TEST_PIECE
  end

  pieces.close
  done = Task.spawn do arrived() end
  body = HTTP.RequestBody(pieces: pieces, done: done)
  dir = folder(options)
  response = Apps.handle_with(app, request.with(body: "".bytes), max_pieces, timeout_ms) do |_conn|
    receive(options, dir, request, body)
  end

  # The body may be left unread (a filter halted, no route); a test must not end with this task running.
  _ = Task.await(done)
  remove(dir)
  response
end

private

MULTIPART_TYPE = "multipart/form-data"

DEFAULT_TYPE = "application/octet-stream"

BODY_METHODS = ["POST", "PUT", "PATCH"]

# The most bytes the server takes in one body (`HTTP.ServerOptions.max_body_bytes`).
SERVER_MAX_BODY = 268_435_456

# How long to wait for the next piece: the server's own timeouts end a body that stalls, so this is only a bound.
PIECE_WAIT_MS = 3_600_000

# The pieces of a body that a test gives as one `Bytes`.
TEST_PIECE = 65_536

# The errors of the reading: the status of the refusal, as `Receiver` asks.
TOO_LARGE = "413"

BAD = "400"

FAILED = "500"

# The part being read: its field, the file it goes to (none for a text field) and what it holds so far.
struct Part
  name: String
  filename: Optional[String]
  content_type: String
  handle: Optional[File.Handle]
  path: String
  size: Int
  text: List[Bytes]
end

# The form so far, while the body arrives. `dir` is made on the first file (`made`); `fields_size` is the size of
# every text field so far.
struct Reading
  dir: String
  made: Bool
  parser: Multipart.Parser
  part: Optional[Part]
  fields: List[URI.Pair]
  files: List[UploadedFile]
  fields_size: Int
  total: Int
end

def arrived() -> Result[Void] = ok()

# Reads the body piece by piece through the parser. A refusal closes the file being written; the folder, with what
# was saved, is removed after the answer by the caller (`answer`, `handle`), in one place for every outcome. A body cut
# by the server (`done` is an error) is the server's refusal (413 over its limit, 431 or 400 for a bad chunk or a
# client that left).
def receive(options: UploadOptions, dir: String, request: HTTP.Request, body: HTTP.RequestBody) -> Result[Form]
  content_type = HTTP.header_values(request.headers, "content-type")[0]
  boundary = Multipart.boundary(content_type)
  return error(BAD) if not boundary.ok?

  reading = Reading(
    dir: dir,
    made: false,
    parser: Multipart.start(boundary.unwrap!),
    part: none,
    fields: [],
    files: [],
    fields_size: 0,
    total: 0,
  )

  while true
    case body.pieces.recv(PIECE_WAIT_MS)
      ok(piece) ->
        case take(options, reading, piece)
          ok(next) -> reading = next
          error(status) ->
            close_part(reading.part)
            return error(status)
        end

      error(_) -> break
    end
  end

  done = Task.await(body.done)
  if not done.ok?
    close_part(reading.part)
    case HTTP.body_refusal(done.message)
      HTTP.Answer.Whole(response) -> return error(response.status.to_s)
      _ -> return error(BAD)
    end
  end

  finished = Multipart.finish(reading.parser)
  ended = end_part(reading)
  if not finished.ok? or not ended.ok?
    close_part(reading.part)
    return error(BAD)
  end

  form = ended.unwrap!
  ok(Form(fields: form.fields, files: form.files))
end

# One piece: its bytes count toward the total, then each event of the parser. The error is the status to answer; a
# part opened by this piece is closed before it is returned.
def take(options: UploadOptions, reading: Reading, piece: Bytes) -> Result[Reading]
  total = reading.total + piece.size
  return error(TOO_LARGE) if total > options.max_total_bytes

  step = Multipart.feed(reading.parser, piece)
  if not step.ok?
    return error(TOO_LARGE) if step.message == Multipart.TOO_MANY_PARTS

    return error(BAD)
  end

  current = reading.with(parser: step.unwrap!.parser, total: total)
  for event in step.unwrap!.events
    case event_of(options, current, event)
      ok(next) -> current = next
      error(status) ->
        close_part(current.part)
        return error(status)
    end
  end

  ok(current)
end

def event_of(options: UploadOptions, reading: Reading, event: Multipart.Event) -> Result[Reading]
  case event
    Multipart.Event.Part(headers) ->
      ended = end_part(reading)
      return error(BAD) if not ended.ok?

      begin_part(ended.unwrap!, headers)

    Multipart.Event.Data(bytes) ->
      case reading.part
        some(part) -> write_part(options, reading, part, bytes)
        none -> ok(reading)
      end

    Multipart.Event.Finished -> ok(reading)
  end
end

# A new part. A file gets a file of its own, named by its number among the files (1, 2, 3), in the folder of the
# request, which the first file makes.
def begin_part(reading: Reading, headers: List[HTTP.Header]) -> Result[Reading]
  disposition = Multipart.disposition(headers)
  return error(BAD) if not disposition.ok?

  found = disposition.unwrap!
  types = headers.select do |field| field.name == "content-type" end
  content_type = DEFAULT_TYPE
  if not types.empty? and types[0].value != ""
    content_type = types[0].value
  end

  part = Part(
    name: found.name,
    filename: found.filename,
    content_type: content_type,
    handle: none,
    path: "",
    size: 0,
    text: [],
  )

  return ok(reading.with(part: some(part))) if found.filename.none?

  if not reading.made and (reading.dir == "" or not Dir.mkdir_private(reading.dir).ok?)
    IO.warn("bond: cannot make a folder for uploads at #{reading.dir}: the dir of UploadOptions must exist")
    return error(FAILED)
  end

  where = Path.join([reading.dir, "#{reading.files.size + 1}"]).unwrap_or("")
  handle = File.open(where, "create_private")
  if where == "" or not handle.ok?
    IO.warn("bond: cannot save an upload in #{reading.dir}")
    return error(FAILED)
  end

  opened = part.with(handle: some(handle.unwrap!), path: where)
  ok(reading.with(made: true, part: some(opened)))
end

# The caps are checked before the bytes are written or kept: a file against `max_file_bytes`, a text field against
# `max_field_bytes`, and all the text fields against `max_fields_bytes`.
def write_part(options: UploadOptions, reading: Reading, part: Part, bytes: Bytes) -> Result[Reading]
  size = part.size + bytes.size
  case part.handle
    some(handle) ->
      return error(TOO_LARGE) if size > options.max_file_bytes

      if not File.write_bytes(handle, bytes).ok?
        IO.warn("bond: cannot write an upload to #{part.path}")
        return error(FAILED)
      end

      ok(reading.with(part: some(part.with(size: size))))

    none ->
      fields_size = reading.fields_size + bytes.size
      return error(TOO_LARGE) if size > options.max_field_bytes or fields_size > options.max_fields_bytes

      grown = part.with(size: size, text: part.text.push(bytes))
      ok(reading.with(part: some(grown), fields_size: fields_size))
  end
end

# The part that was being read goes into the form: a text field as UTF-8 (an error when it is not), a file with its
# size (a file input left empty, with no filename and no bytes, is dropped, as browsers send it).
def end_part(reading: Reading) -> Result[Reading]
  case reading.part
    none -> ok(reading)
    some(part) ->
      closed = reading.with(part: none)
      case part.handle
        none ->
          value = try String.from_bytes(Bytes.concat(part.text))
          ok(closed.with(fields: closed.fields.push(URI.Pair(name: part.name, value: value))))

        some(handle) ->
          _ = File.close(handle)
          raw = part.filename.unwrap_or("")
          if raw == "" and part.size == 0
            _ = Path.remove(part.path)
            return ok(closed)
          end

          upload = UploadedFile(
            name: part.name,
            filename: Multipart.safe_filename(raw),
            content_type: part.content_type,
            path: part.path,
            size: part.size,
          )

          ok(closed.with(files: closed.files.push(upload)))
      end
  end
end

def close_part(part: Optional[Part]) -> Void
  case part
    some(open) ->
      case open.handle
        some(handle) -> _ = File.close(handle)
        none -> nil
      end

    none -> nil
  end
end

# The path of the private folder for the files of one request, under the folder of the options or the system's; it
# is made on the first file. "" when the path cannot be built (then a file is a 500).
def folder(options: UploadOptions) -> String
  root = options.dir
  if root == ""
    root = system_temp()
  end

  Path.join([root, "bond-upload-#{OpenSSL.Random.hex(16)}"]).unwrap_or("")
end

def system_temp() -> String
  for name in ["TMPDIR", "TEMP", "TMP"]
    case System.env(name)
      ok(value) -> return value if value != ""

      error(_) -> nil
    end
  end

  "/tmp"
end

# A folder that was never made is no error (`Path.remove` of a missing path is `ok`).
def remove(dir: String) -> Void
  if dir != "" and not Path.remove(dir).ok?
    IO.warn("bond: cannot remove the upload folder #{dir}")
  end
end
