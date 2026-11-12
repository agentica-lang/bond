## A streaming parser of `multipart/form-data` (RFC 7578, with the framing of RFC 2046 section 5.1.1). It takes the
## body in pieces of any size and gives events: the headers of each part, its data in pieces, and the end. It holds at
## most one piece and the bytes of a delimiter, so a big file goes through it without being kept. It does no I/O.
##
## The bytes are searched as Latin-1 text, where one character is one byte, so `String.index_of` finds a delimiter
## and its index is the byte offset. A piece is read from an offset that moves forward, and each search looks at a
## window that grows only when it finds nothing, so a piece of many small parts costs its size, not its size times its
## parts.

import HTTP from "std/http"

# Where the parser is: before the first delimiter, right after a delimiter (the rest of its line, or `--` for the
# last one), in the headers of a part, in its data, or after the last delimiter (the epilogue, which is ignored).
PREAMBLE = 0
AFTER_DELIMITER = 1
HEADERS = 2
DATA = 3
DONE = 4

CRLF = "\r\n"
HEAD_END = "\r\n\r\n"
LAST = "--"

# The longest header section of a part, and the longest rest of a delimiter line (transport padding).
MAX_HEAD_BYTES = 16_384
MAX_PADDING_BYTES = 256

# The characters of a boundary (RFC 2046 `bchars`): letters, digits and these, a space only inside.
BOUNDARY_SYMBOLS = "'()+_,-./:=? "
MAX_BOUNDARY = 70
MAX_FILENAME = 255

# The first window of a search; each next one is 4 times larger.
SEARCH_WINDOW = 4096

## The most parts of a body, and the error of `feed` for a body with more.
export MAX_PARTS = 1000
export TOO_MANY_PARTS = "the multipart body has more than 1000 parts"

## The state between two pieces. `delimiter` is CRLF, `--` and the boundary; `buffer` holds what is not decided yet;
## `parts` counts the parts so far.
export struct Parser
  delimiter: String
  phase: Int
  buffer: Bytes
  parts: Int = 0
end

## What a piece told: a new part with its headers (names in lowercase), a piece of the data of the current part, or
## the last delimiter.
export enum Event
  Part(List[HTTP.Header])
  Data(Bytes)
  Finished
end

export struct Step
  parser: Parser
  events: List[Event]
end

# Where one step of `feed` left the piece: the phase, the offset of the bytes not used yet, and what it found.
struct Move
  phase: Int
  at: Int
  events: List[Event]
end

# A parameter of a header and the index where it ended (its `;` or the end).
struct Item
  header: HTTP.Header
  next: Int
end

## The `Content-Disposition` of a part: the field `name`, and the `filename` of a file (`none` for a text field).
export struct Disposition
  name: String
  filename: Optional[String]
end

## The boundary of a `Content-Type` of `multipart/form-data` (the type in any case, the boundary quoted or not), or an
## error when the type is another or the boundary is missing or not 1 to 70 characters of RFC 2046.
export def boundary(content_type: String) -> Result[String]
  params = parameters(content_type)
  if params.empty? or params[0].name.downcase != "multipart/form-data" or params[0].value != ""
    return error("the content type is not multipart/form-data")
  end

  found = params.drop(1).select do |param| param.name.downcase == "boundary" end
  return error("the content type has no boundary") if found.size != 1

  text = found[0].value
  if text.empty? or text.length > MAX_BOUNDARY or text.end_with?(" ")
    return error("the boundary must be 1 to #{MAX_BOUNDARY} characters")
  end

  if not text.split("").all? do |ch| boundary_char?(ch) end
    return error("the boundary has a character that RFC 2046 does not allow")
  end

  ok(text)
end

## A parser for a body with this boundary (from `boundary`). The body may start with the first delimiter or with a
## preamble before it: the parser reads it as if a line break came first.
export def start(boundary: String) -> Parser
  Parser(delimiter: "#{CRLF}--#{boundary}", phase: PREAMBLE, buffer: CRLF.bytes)
end

## The events of the next piece of the body. An error when the body is not `multipart/form-data` as RFC 2046 frames
## it: a delimiter line with other text after it, or the headers of a part over 16 KiB or not `Name: value` lines; and
## `TOO_MANY_PARTS` when it has more than `MAX_PARTS` parts.
export def feed(parser: Parser, piece: Bytes) -> Result[Step]
  buffer = parser.buffer + piece
  current = Move(phase: parser.phase, at: 0, events: [])
  events: List[Event] = []
  parts = parser.parts
  while true
    # A step that cannot go on gives back the move it got, so that move must carry no event.
    step = try advance(parser.delimiter, buffer, current.with(events: []))
    moved = not step.events.empty? or step.phase != current.phase or step.at != current.at
    for event in step.events
      case event
        Event.Part(_) -> parts = parts + 1
        _ -> nil
      end

      events = events.push(event)
    end

    return error(TOO_MANY_PARTS) if parts > MAX_PARTS

    current = step
    break if not moved or current.phase == DONE
  end

  rest = buffer.drop(current.at)
  if current.phase == DONE
    rest = "".bytes
  end

  ok(Step(parser: parser.with(phase: current.phase, buffer: rest, parts: parts), events: events))
end

## An error when the body ended before its last delimiter, so a part may be cut.
export def finish(parser: Parser) -> Result[Void]
  return error("the multipart body ends before its last boundary") if parser.phase != DONE

  ok()
end

## The `Content-Disposition` of the headers of a part: `form-data` with a `name` (it may be empty) and maybe a
## `filename`. An error when there is none, two, another type, or no `name`.
export def disposition(headers: List[HTTP.Header]) -> Result[Disposition]
  values = headers.select do |field| field.name == "content-disposition" end
  return error("a part must have one Content-Disposition") if values.size != 1

  params = parameters(values[0].value)
  if params.empty? or params[0].name.downcase != "form-data" or params[0].value != ""
    return error("the Content-Disposition of a part must be form-data")
  end

  rest = params.drop(1)
  names = rest.select do |param| param.name.downcase == "name" end
  return error("a part must have one name") if names.size != 1

  files = rest.select do |param| param.name.downcase == "filename" end
  filename: Optional[String] = none
  return error("a part has two filenames") if files.size > 1

  if files.size == 1
    filename = some(files[0].value)
  end

  ok(Disposition(name: names[0].value, filename: filename))
end

## The name of a file as a client gave it, made safe to show: the part after the last `/` or `\` (an old browser sends
## the whole path), with no control character (C0, DEL, C1) and no mark that turns the direction of the text (so
## `\u202Egpj.exe` cannot show as `exe.jpg`), at most 255 characters, and `file` for a name that is empty, `.` or
## `..`. It is never a path on the server: Bond saves a file under a name of its own.
export def safe_filename(raw: String) -> String
  last = raw.split("/").last.split("\\").last
  chars = last.split("").select do |ch| shown?(ch.code) end
  kept = chars.join("").strip
  return "file" if kept == "" or kept == "." or kept == ".."

  return kept.slice(0, MAX_FILENAME) if kept.length > MAX_FILENAME

  kept
end

# One step of the state machine from `move.at`: the buffer is used as far as the phase can go with it. A step that
# needs more bytes gives the move as it was (no event, the same phase and offset).
def advance(delimiter: String, buffer: Bytes, move: Move) -> Result[Move]
  return ok(skip_preamble(delimiter, buffer, move)) if move.phase == PREAMBLE

  return after_delimiter(buffer, move) if move.phase == AFTER_DELIMITER

  return headers(buffer, move) if move.phase == HEADERS

  return ok(data(delimiter, buffer, move)) if move.phase == DATA

  ok(Move(phase: DONE, at: buffer.size, events: []))
end

def skip_preamble(delimiter: String, buffer: Bytes, move: Move) -> Move
  case find(buffer, move.at, delimiter)
    some(at) -> Move(phase: AFTER_DELIMITER, at: at + delimiter.length, events: [])
    none -> move.with(at: tail(delimiter, buffer, move.at))
  end
end

# After a delimiter: `--` ends the body; else the line may have spaces and tabs and then ends.
def after_delimiter(buffer: Bytes, move: Move) -> Result[Move]
  return ok(move) if buffer.size - move.at < 2

  return ok(Move(phase: DONE, at: buffer.size, events: [Event.Finished])) if buffer.slice(move.at, 2) == LAST.bytes

  case find(buffer, move.at, CRLF)
    some(at) ->
      padding = latin1(buffer.slice(move.at, at - move.at))
      if not padding.split("").all? do |ch| ch == " " or ch == "\t" end
        return error("a boundary line has more text after the boundary")
      end

      ok(Move(phase: HEADERS, at: at + 2, events: []))

    none ->
      return error("a boundary line has more text after the boundary") if buffer.size - move.at > MAX_PADDING_BYTES

      ok(move)
  end
end

def headers(buffer: Bytes, move: Move) -> Result[Move]
  if buffer.size - move.at >= 2 and buffer.slice(move.at, 2) == CRLF.bytes
    return ok(Move(phase: DATA, at: move.at + 2, events: [Event.Part([])]))
  end

  case find(buffer, move.at, HEAD_END)
    some(at) ->
      return error("the headers of a part are too long") if at - move.at > MAX_HEAD_BYTES

      fields = try header_lines(buffer.slice(move.at, at - move.at))
      ok(Move(phase: DATA, at: at + HEAD_END.length, events: [Event.Part(fields)]))

    none ->
      return error("the headers of a part are too long") if buffer.size - move.at > MAX_HEAD_BYTES

      ok(move)
  end
end

# The data of a part goes out as it comes, except the last bytes, which may be the start of the delimiter.
def data(delimiter: String, buffer: Bytes, move: Move) -> Move
  case find(buffer, move.at, delimiter)
    some(at) ->
      events: List[Event] = []
      if at > move.at
        events = [Event.Data(buffer.slice(move.at, at - move.at))]
      end

      Move(phase: AFTER_DELIMITER, at: at + delimiter.length, events: events)

    none ->
      kept = tail(delimiter, buffer, move.at)
      return move if kept <= move.at

      move.with(at: kept, events: [Event.Data(buffer.slice(move.at, kept - move.at))])
  end
end

# Where the end of the buffer that may be the start of a delimiter begins: one byte less than a delimiter, and never
# before `at`.
def tail(delimiter: String, buffer: Bytes, at: Int) -> Int
  start = buffer.size - (delimiter.length - 1)
  return at if start < at

  start
end

# `Name: value` lines; the names in lowercase, the values as UTF-8 (Latin-1 when they are not).
def header_lines(head: Bytes) -> Result[List[HTTP.Header]]
  text = String.from_bytes(head).unwrap_or(latin1(head))
  fields: List[HTTP.Header] = []
  for line in text.split(CRLF)
    case line.index_of(":")
      some(at) ->
        name = line.slice(0, at).strip.downcase
        return error("a header of a part has no name") if name == ""

        fields = fields.push(HTTP.Header(name: name, value: line.slice(at + 1, line.length - at - 1).strip))

      none -> return error("a header line of a part has no colon")
    end
  end

  ok(fields)
end

# The value and the parameters of a header such as `form-data; name="a"; filename="b.txt"`: the first item is the
# value (as a name with an empty value), then each `key=value`, a quoted value unquoted. In quotes only `\"` and `\\`
# are escapes, as browsers write them: another backslash stays, so `C:\temp\a.txt` keeps its path for `safe_filename`.
def parameters(header: String) -> List[HTTP.Header]
  items: List[HTTP.Header] = []
  chars = header.split("")
  at = 0
  while at <= chars.size
    item = read_item(chars, at)
    if not item.header.name.empty?
      items = items.push(item.header)
    end

    at = item.next + 1
  end

  items
end

# One `key=value` from `at` to the next `;` outside quotes.
def read_item(chars: List[String], at: Int) -> Item
  key: List[String] = []
  value: List[String] = []
  in_value = false
  quoted = false
  escaped = false
  index = at
  while index < chars.size
    ch = chars[index]
    if quoted
      if escaped
        if ch != "\"" and ch != "\\"
          value = value.push("\\")
        end

        value = value.push(ch)
        escaped = false
      elsif ch == "\\"
        escaped = true
      elsif ch == "\""
        quoted = false
      else
        value = value.push(ch)
      end
    elsif ch == ";"
      break
    elsif in_value
      if ch == "\"" and value.join("").strip == ""
        quoted = true
        value = []
      else
        value = value.push(ch)
      end
    elsif ch == "="
      in_value = true
    else
      key = key.push(ch)
    end

    index = index + 1
  end

  text = value.join("")
  if not quoted
    text = text.strip
  end

  Item(header: HTTP.Header(name: key.join("").strip, value: text), next: index)
end

# The first `text` in `bytes` from `at`, as an offset in `bytes`. The search looks at a window from `at` that grows 4
# times while it finds nothing, so a match near `at` costs little, and the whole search costs a few times the bytes up
# to the match (or to the end).
def find(bytes: Bytes, at: Int, text: String) -> Optional[Int]
  rest = bytes.size - at
  window = SEARCH_WINDOW
  while true
    size = window
    if size > rest
      size = rest
    end

    case latin1(bytes.slice(at, size)).index_of(text)
      some(found) -> return some(at + found)
      none -> return none if size == rest
    end

    window = window * 4
  end

  none
end

def latin1(bytes: Bytes) -> String = bytes.decode("latin-1").unwrap!

# A character `safe_filename` keeps: not a control character (C0, DEL, C1) and not a mark of the direction of the text
# (LRM, RLM, ALM, the embeddings and overrides U+202A to U+202E, the isolates U+2066 to U+2069).
def shown?(code: Int) -> Bool
  return false if code < 32 or (code >= 127 and code <= 159)

  return false if code == 0x200E or code == 0x200F or code == 0x061C

  not ((code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069))
end

def boundary_char?(ch: String) -> Bool
  code = ch.code
  letter = (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
  letter or (code >= 48 and code <= 57) or BOUNDARY_SYMBOLS.include?(ch)
end
