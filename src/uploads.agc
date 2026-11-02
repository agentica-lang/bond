## File uploads: a `multipart/form-data` body read as it arrives, its files saved to a private temporary folder with
## a size cap, and its text fields kept for `Bond.form`. The folder is removed after the answer.

import HTTP from "std/http"
import URI from "std/uri"
import Apps from "app"
import Conns from "conn"
import Multipart from "multipart"
import {App, UploadOptions} from "app"
import {Conn, Form, UploadedFile} from "conn"

MULTIPART_TYPE = "multipart/form-data"
DEFAULT_TYPE = "application/octet-stream"

# The most parts of one body, so a body of many tiny parts cannot make the parser loop for long.
MAX_PARTS = 1_000

# The most bytes the server takes in one body (`HttpServerOptions.max_body_bytes`).
SERVER_MAX_BODY = 268_435_456

# How long to wait for the next piece: the server's own timeouts end a body that stalls, so this is only a bound.
PIECE_WAIT_MS = 3_600_000

# The pieces of a body that a test gives as one `Bytes`.
TEST_PIECE = 65_536

# The errors of the reading, which `refusal` turns into an answer: a status, or the server's message of a body it
# cut after `SERVER`.
TOO_LARGE = "413"
BAD = "400"
FAILED = "500"
SERVER = "server: "

# What `receive` read: the form, and the folder of its files.
struct Received
  form: Form
  dir: String
end

# The part being read: its field, the file it goes to (none for a text field) and what it holds so far.
struct Part
  name: String
  filename: Optional[String]
  content_type: String
  handle: Optional[FileHandle]
  path: String
  size: Int
  text: List[Bytes]
end

# The form so far, while the body arrives.
struct Reading
  parser: Multipart.Parser
  part: Optional[Part]
  fields: List[URI.Pair]
  files: List[UploadedFile]
  parts: Int
  total: Int
end

## Turns on uploads: a request whose `Content-Type` is `multipart/form-data` is read as it arrives, before the
## filters run. Each file goes to a new private folder under `options.dir` (a name of Bond's own, never the client's),
## and its text fields to `Bond.form`, `form_all` and `form_int`. `Bond.file(conn, name)` gives a file. A file over
## `max_file_bytes`, or a body over `max_total_bytes`, is a 413 that closes the connection, and the handler does not
## run; a body that is not `multipart/form-data` as RFC 7578 frames it is a 400. The folder and every file in it are
## removed when the answer is ready (for a stream, before it is sent), so a handler that keeps a file moves it. Other
## requests keep the body limit of the server (`max_body_bytes` of `Bond.start_with`); the server takes a body up to
## `max_total_bytes` for these. The program stops when a limit is below 1, when `max_file_bytes` is above
## `max_total_bytes`, or when `max_total_bytes` is above 256 MiB.
export def uploads(app: App, options: UploadOptions = UploadOptions()) -> App
  if options.max_file_bytes < 1 or options.max_total_bytes < options.max_file_bytes
    bad: Result[App] = error("bond: the upload limits must be 1 or more, max_file_bytes at most max_total_bytes")
    return bad.unwrap!
  end

  if options.max_total_bytes > SERVER_MAX_BODY
    bad: Result[App] = error("bond: max_total_bytes of uploads must be at most #{SERVER_MAX_BODY}")
    return bad.unwrap!
  end

  return app.with(uploads: some(options))
end

## The first file of the field `name`, or an error that makes a 400 when there is none (so `try Bond.file(...)`
## answers it). A field that came as text is no file.
export def file(conn: Conn, name: String) -> Result[UploadedFile]
  found = file_all(conn, name)
  if found.empty?
    return Conns.bad_request("file #{name} is missing")
  end

  return ok(found[0])
end

## Every file of the field `name`, in order (`<input type="file" multiple>`): an empty list when there is none.
export def file_all(conn: Conn, name: String) -> List[UploadedFile]
  case conn.form
    some(parts) -> return parts.files.select do |upload| upload.name == name end
    none -> return []
  end
end

## The upload options when they apply to the request: the app has uploads and the body is `multipart/form-data`.
export def applies(app: App, request: HttpRequest) -> Optional[UploadOptions]
  types = HTTP.header_values(request.headers, "content-type")
  if types.size != 1 or types[0].split(";")[0].strip.downcase != MULTIPART_TYPE
    return none
  end

  return app.uploads
end

## The body limit of the server: the larger of the one of the other requests and the uploads' total.
export def server_limit(app: App, limit: Int) -> Int
  case app.uploads
    some(options) ->
      if options.max_total_bytes > limit
        return options.max_total_bytes
      end

      return limit

    none -> return limit
  end
end

## The answer of `HTTP.serve` for a request that `applies`: the body read to the files, the app with the form, and
## the folder removed; or the refusal of the body.
export def answer(app: App, options: UploadOptions, request: HttpRequest, body: HTTP.RequestBody) -> HTTP.Answer
  case receive(options, request, body)
    ok(received) ->
      answered = Apps.handle_answer(app, request.with(body: "".bytes), some(received.form))
      remove(received.dir)
      return answered

    error(problem) -> return refusal(problem)
  end
end

## Like `answer`, for `Testing.request`: the body is given whole, in pieces of 64 KiB, and the answer is whole.
export def handle(
  app: App,
  options: UploadOptions,
  request: HttpRequest,
  max_pieces: Int,
  timeout_ms: Int,
) -> HttpResponse
  pieces: Channel[Bytes] = Channel.new(request.body.size / TEST_PIECE + 1)
  at = 0
  while at < request.body.size
    pieces.send(request.body.drop(at).take(TEST_PIECE), 0).unwrap!
    at = at + TEST_PIECE
  end

  pieces.close
  done = Task.spawn() do arrived() end
  outcome = receive(options, request, HTTP.RequestBody(pieces: pieces, done: done))
  # A refusal may come before `receive` awaits the task; a test must not end with it running.
  Task.await(done)
  case outcome
    ok(received) ->
      empty = request.with(body: "".bytes)
      response = Apps.handle(app, empty, max_pieces, timeout_ms, some(received.form))
      remove(received.dir)
      return response

    error(problem) ->
      case refusal(problem)
        HTTP.Answer.Whole(response) -> return response
        _ -> return HttpResponse(status: 500, headers: [], body: "".bytes)
      end
  end
end

def arrived() -> Result[Void]
  return ok()
end

# Reads the body piece by piece through the parser. A refusal removes what was saved; a body cut by the server
# (`done` is an error) is the server's refusal (413 over its limit, 400 for a bad chunk or a client that left).
def receive(options: UploadOptions, request: HttpRequest, body: HTTP.RequestBody) -> Result[Received]
  content_type = HTTP.header_values(request.headers, "content-type")[0]
  boundary = Multipart.boundary(content_type)
  if not boundary.ok?
    return error(BAD)
  end

  dir = try make_dir(options)
  reading = Reading(parser: Multipart.start(boundary.unwrap!), part: none, fields: [], files: [], parts: 0, total: 0)
  while true
    case body.pieces.recv(PIECE_WAIT_MS)
      ok(piece) ->
        case take(options, dir, reading, piece)
          ok(next) -> reading = next
          error(status) ->
            close_part(reading.part)
            remove(dir)
            return error(status)
        end

      error(_) -> break
    end
  end

  done = Task.await(body.done)
  if not done.ok?
    close_part(reading.part)
    remove(dir)
    return error("#{SERVER}#{done.message}")
  end

  if not Multipart.finish(reading.parser).ok?
    close_part(reading.part)
    remove(dir)
    return error(BAD)
  end

  finished = end_part(reading)
  if not finished.ok?
    remove(dir)
    return error(BAD)
  end

  form = finished.unwrap!
  return ok(Received(form: Form(fields: form.fields, files: form.files), dir: dir))
end

# One piece: its bytes count toward the total, then each event of the parser. The error is the status to answer.
def take(options: UploadOptions, dir: String, reading: Reading, piece: Bytes) -> Result[Reading]
  total = reading.total + piece.size
  if total > options.max_total_bytes
    return error(TOO_LARGE)
  end

  step = Multipart.feed(reading.parser, piece)
  if not step.ok?
    return error(BAD)
  end

  current = reading.with(parser: step.unwrap!.parser, total: total)
  for event in step.unwrap!.events
    current = try event_of(options, dir, current, event)
  end

  return ok(current)
end

def event_of(options: UploadOptions, dir: String, reading: Reading, event: Multipart.Event) -> Result[Reading]
  case event
    Multipart.Event.Part(headers) ->
      ended = end_part(reading)
      if not ended.ok?
        return error(BAD)
      end

      done = ended.unwrap!
      if done.parts >= MAX_PARTS
        return error(TOO_LARGE)
      end

      part = try begin_part(dir, done.parts, headers)
      return ok(done.with(part: some(part), parts: done.parts + 1))

    Multipart.Event.Data(bytes) ->
      case reading.part
        some(part) ->
          grown = try write_part(options, part, bytes)
          return ok(reading.with(part: some(grown)))

        none -> return ok(reading)
      end

    Multipart.Event.Finished -> return ok(reading)
  end
end

# A new part: a file gets a file of its own in the folder, named by its number.
def begin_part(dir: String, number: Int, headers: List[Header]) -> Result[Part]
  disposition = Multipart.disposition(headers)
  if not disposition.ok?
    return error(BAD)
  end

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
  if found.filename.none?
    return ok(part)
  end

  where = Path.join([dir, "#{number + 1}"]).unwrap_or("")
  handle = File.open(where, "create_private")
  if where == "" or not handle.ok?
    IO.warn("bond: cannot save an upload in #{dir}")
    return error(FAILED)
  end

  return ok(part.with(handle: some(handle.unwrap!), path: where))
end

def write_part(options: UploadOptions, part: Part, bytes: Bytes) -> Result[Part]
  size = part.size + bytes.size
  case part.handle
    some(handle) ->
      if size > options.max_file_bytes
        return error(TOO_LARGE)
      end

      if not File.write_bytes(handle, bytes).ok?
        IO.warn("bond: cannot write an upload to #{part.path}")
        return error(FAILED)
      end

      return ok(part.with(size: size))

    none -> return ok(part.with(size: size, text: part.text.push(bytes)))
  end
end

# The part that was being read goes into the form: a text field as UTF-8 (an error when it is not), a file with its
# size (a file input left empty, with no filename and no bytes, is dropped, as browsers send it).
def end_part(reading: Reading) -> Result[Reading]
  case reading.part
    none -> return ok(reading)
    some(part) ->
      closed = reading.with(part: none)
      case part.handle
        none ->
          value = try String.from_bytes(Bytes.concat(part.text))
          return ok(closed.with(fields: closed.fields.push(URI.Pair(name: part.name, value: value))))

        some(handle) ->
          File.close(handle)
          raw = part.filename.unwrap_or("")
          if raw == "" and part.size == 0
            Path.remove(part.path)
            return ok(closed)
          end

          upload = UploadedFile(
            name: part.name,
            filename: Multipart.safe_filename(raw),
            content_type: part.content_type,
            path: part.path,
            size: part.size,
          )
          return ok(closed.with(files: closed.files.push(upload)))
      end
  end
end

def close_part(part: Optional[Part]) -> Void
  case part
    some(open) ->
      case open.handle
        some(handle) -> File.close(handle)
        none -> nil
      end

    none -> nil
  end
end

# A new private folder for the files of one request, under the folder of the options or the system's.
def make_dir(options: UploadOptions) -> Result[String]
  root = options.dir
  if root == ""
    root = system_temp()
  end

  where = Path.join([root, "bond-upload-#{SecureRandom.hex(16)}"])
  if not where.ok? or not Dir.mkdir_private(where.unwrap!).ok?
    IO.warn("bond: cannot make a folder for uploads under #{root}")
    return error(FAILED)
  end

  return ok(where.unwrap!)
end

def system_temp() -> String
  for name in ["TMPDIR", "TEMP", "TMP"]
    case System.env(name)
      ok(value) ->
        if value != ""
          return value
        end

      error(_) -> nil
    end
  end

  return "/tmp"
end

def remove(dir: String) -> Void
  if not Path.remove(dir).ok?
    IO.warn("bond: cannot remove the upload folder #{dir}")
  end
end

# The answer to a body that `receive` refused: the server's own for a body it cut, else the status, with no body and
# `Connection: close` (the rest of the body is not read).
def refusal(problem: String) -> HTTP.Answer
  if problem.start_with?(SERVER)
    return HTTP.body_refusal(problem.slice(SERVER.length, problem.length - SERVER.length))
  end

  headers = [Header(name: "connection", value: "close")]
  return HTTP.Answer.Whole(HttpResponse(status: problem.to_i!, headers: headers, body: "".bytes))
end
