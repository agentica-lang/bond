## A streaming parser of `multipart/form-data` (RFC 7578, with the framing of RFC 2046 section 5.1.1). It takes the
## body in pieces of any size and gives events: the headers of each part, its data in pieces, and the end. It holds at
## most one piece and the bytes of a delimiter, so a big file goes through it without being kept. It does no I/O.
##
## The bytes are searched as Latin-1 text, where one character is one byte, so `String.index_of` finds a delimiter
## and its index is the byte offset.

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

## The state between two pieces. `delimiter` is CRLF, `--` and the boundary; `buffer` holds what is not decided yet.
export struct Parser
  delimiter: String
  phase: Int
  buffer: Bytes
end

## What a piece told: a new part with its headers (names in lowercase), a piece of the data of the current part, or
## the last delimiter.
export enum Event
  Part(List[Header])
  Data(Bytes)
  Finished
end

export struct Step
  parser: Parser
  events: List[Event]
end

# A parameter of a header and the index where it ended (its `;` or the end).
struct Item
  header: Header
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
  if found.size != 1
    return error("the content type has no boundary")
  end

  text = found[0].value
  if text.empty? or text.length > MAX_BOUNDARY or text.end_with?(" ")
    return error("the boundary must be 1 to #{MAX_BOUNDARY} characters")
  end

  if not text.split("").all? do |ch| boundary_char?(ch) end
    return error("the boundary has a character that RFC 2046 does not allow")
  end

  return ok(text)
end

## A parser for a body with this boundary (from `boundary`). The body may start with the first delimiter or with a
## preamble before it: the parser reads it as if a line break came first.
export def start(boundary: String) -> Parser
  return Parser(delimiter: "#{CRLF}--#{boundary}", phase: PREAMBLE, buffer: CRLF.bytes)
end

## The events of the next piece of the body. An error when the body is not `multipart/form-data` as RFC 2046 frames
## it: a delimiter line with other text after it, or the headers of a part over 16 KiB or not `Name: value` lines.
export def feed(parser: Parser, piece: Bytes) -> Result[Step]
  current = parser.with(buffer: parser.buffer + piece)
  events: List[Event] = []
  while true
    step = try advance(current)
    moved = not step.events.empty? or step.parser.phase != current.phase
    moved = moved or step.parser.buffer.size != current.buffer.size
    current = step.parser
    events = events.concat(step.events)
    if not moved or current.phase == DONE
      break
    end
  end

  return ok(Step(parser: current, events: events))
end

## An error when the body ended before its last delimiter, so a part may be cut.
export def finish(parser: Parser) -> Result[Void]
  if parser.phase != DONE
    return error("the multipart body ends before its last boundary")
  end

  return ok()
end

## The `Content-Disposition` of the headers of a part: `form-data` with a `name` (it may be empty) and maybe a
## `filename`. An error when there is none, two, another type, or no `name`.
export def disposition(headers: List[Header]) -> Result[Disposition]
  values = headers.select do |field| field.name == "content-disposition" end
  if values.size != 1
    return error("a part must have one Content-Disposition")
  end

  params = parameters(values[0].value)
  if params.empty? or params[0].name.downcase != "form-data" or params[0].value != ""
    return error("the Content-Disposition of a part must be form-data")
  end

  rest = params.drop(1)
  names = rest.select do |param| param.name.downcase == "name" end
  if names.size != 1
    return error("a part must have one name")
  end

  files = rest.select do |param| param.name.downcase == "filename" end
  filename: Optional[String] = none
  if files.size > 1
    return error("a part has two filenames")
  end

  if files.size == 1
    filename = some(files[0].value)
  end

  return ok(Disposition(name: names[0].value, filename: filename))
end

## The name of a file as a client gave it, made safe to show: the part after the last `/` or `\` (an old browser sends
## the whole path), with no control character, at most 255 characters, and `file` for a name that is empty, `.` or
## `..`. It is never a path on the server: Bond saves a file under a name of its own.
export def safe_filename(raw: String) -> String
  last = raw.split("/").last.split("\\").last
  kept = last.split("").select do |ch| ch.code >= 32 and ch.code != 127 end.join("").strip
  if kept == "" or kept == "." or kept == ".."
    return "file"
  end

  if kept.length > MAX_FILENAME
    return kept.slice(0, MAX_FILENAME)
  end

  return kept
end

# One step of the state machine: the buffer is used as far as the phase can go with it. A step that needs more bytes
# gives the parser as it was (no event, the same phase and buffer).
def advance(parser: Parser) -> Result[Step]
  if parser.phase == PREAMBLE
    return ok(skip_preamble(parser))
  end

  if parser.phase == AFTER_DELIMITER
    return after_delimiter(parser)
  end

  if parser.phase == HEADERS
    return headers(parser)
  end

  if parser.phase == DATA
    return ok(data(parser))
  end

  return ok(Step(parser: parser.with(buffer: "".bytes), events: []))
end

def skip_preamble(parser: Parser) -> Step
  case find(parser.buffer, parser.delimiter)
    some(at) ->
      rest = parser.buffer.drop(at + parser.delimiter.length)
      return Step(parser: parser.with(phase: AFTER_DELIMITER, buffer: rest), events: [])

    none -> return Step(parser: parser.with(buffer: tail(parser)), events: [])
  end
end

# After a delimiter: `--` ends the body; else the line may have spaces and tabs and then ends.
def after_delimiter(parser: Parser) -> Result[Step]
  buffer = parser.buffer
  if buffer.size < 2
    return ok(Step(parser: parser, events: []))
  end

  if buffer.take(2) == LAST.bytes
    return ok(Step(parser: parser.with(phase: DONE, buffer: "".bytes), events: [Event.Finished]))
  end

  case find(buffer, CRLF)
    some(at) ->
      padding = latin1(buffer.take(at))
      if not padding.split("").all? do |ch| ch == " " or ch == "\t" end
        return error("a boundary line has more text after the boundary")
      end

      return ok(Step(parser: parser.with(phase: HEADERS, buffer: buffer.drop(at + 2)), events: []))

    none ->
      if buffer.size > MAX_PADDING_BYTES
        return error("a boundary line has more text after the boundary")
      end

      return ok(Step(parser: parser, events: []))
  end
end

def headers(parser: Parser) -> Result[Step]
  buffer = parser.buffer
  if buffer.size >= 2 and buffer.take(2) == CRLF.bytes
    return ok(Step(parser: parser.with(phase: DATA, buffer: buffer.drop(2)), events: [Event.Part([])]))
  end

  case find(buffer, HEAD_END)
    some(at) ->
      if at > MAX_HEAD_BYTES
        return error("the headers of a part are too long")
      end

      fields = try header_lines(buffer.take(at))
      next_parser = parser.with(phase: DATA, buffer: buffer.drop(at + HEAD_END.length))
      return ok(Step(parser: next_parser, events: [Event.Part(fields)]))

    none ->
      if buffer.size > MAX_HEAD_BYTES
        return error("the headers of a part are too long")
      end

      return ok(Step(parser: parser, events: []))
  end
end

# The data of a part goes out as it comes, except the last bytes, which may be the start of the delimiter.
def data(parser: Parser) -> Step
  buffer = parser.buffer
  case find(buffer, parser.delimiter)
    some(at) ->
      events: List[Event] = []
      if at > 0
        events = [Event.Data(buffer.take(at))]
      end

      rest = buffer.drop(at + parser.delimiter.length)
      return Step(parser: parser.with(phase: AFTER_DELIMITER, buffer: rest), events: events)

    none ->
      kept = tail(parser)
      sent = buffer.size - kept.size
      if sent <= 0
        return Step(parser: parser, events: [])
      end

      return Step(parser: parser.with(buffer: kept), events: [Event.Data(buffer.take(sent))])
  end
end

# The end of the buffer that may be the start of a delimiter: one byte less than a delimiter.
def tail(parser: Parser) -> Bytes
  keep = parser.delimiter.length - 1
  if parser.buffer.size <= keep
    return parser.buffer
  end

  return parser.buffer.drop(parser.buffer.size - keep)
end

# `Name: value` lines; the names in lowercase, the values as UTF-8 (Latin-1 when they are not).
def header_lines(head: Bytes) -> Result[List[Header]]
  text = String.from_bytes(head).unwrap_or(latin1(head))
  fields: List[Header] = []
  for line in text.split(CRLF)
    case line.index_of(":")
      some(at) ->
        name = line.slice(0, at).strip.downcase
        if name == ""
          return error("a header of a part has no name")
        end

        fields = fields.push(Header(name: name, value: line.slice(at + 1, line.length - at - 1).strip))

      none -> return error("a header line of a part has no colon")
    end
  end

  return ok(fields)
end

# The value and the parameters of a header such as `form-data; name="a"; filename="b.txt"`: the first item is the
# value (as a name with an empty value), then each `key=value`, a quoted value with `\` escapes unquoted.
def parameters(header: String) -> List[Header]
  items: List[Header] = []
  chars = header.split("")
  at = 0
  while at <= chars.size
    item = read_item(chars, at)
    if not item.header.name.empty?
      items = items.push(item.header)
    end

    at = item.next + 1
  end

  return items
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

  return Item(header: Header(name: key.join("").strip, value: text), next: index)
end

def find(bytes: Bytes, text: String) -> Optional[Int]
  return latin1(bytes).index_of(text)
end

def latin1(bytes: Bytes) -> String
  return bytes.decode("latin-1").unwrap!
end

def boundary_char?(ch: String) -> Bool
  code = ch.code
  letter = (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
  return letter or (code >= 48 and code <= 57) or BOUNDARY_SYMBOLS.include?(ch)
end
