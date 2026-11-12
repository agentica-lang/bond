import HTTP from "std/http"
import Multipart from "../src/multipart"

BOUNDARY = "XyZ"
BODY = [
  "--XyZ\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nbuy milk\r\n",
  "--XyZ\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\n",
  "line one\r\nline two --XyZ not yet\r\n--XyZ--\r\nepilogue",
].join("")

# What the parser tells for a body cut into pieces of `size` bytes, as text: `part <name> <filename>` for a part, its
# data joined, and `end`.
struct Told
  lines: List[String]
  finished: Bool
end

def tell(body: Bytes, size: Int) -> Result[Told]
  parser = Multipart.start(BOUNDARY)
  lines: List[String] = []
  data: List[Bytes] = []
  at = 0
  while at < body.size
    step = try Multipart.feed(parser, body.drop(at).take(size))
    parser = step.parser
    for event in step.events
      case event
        Multipart.Event.Part(headers) ->
          if not data.empty?
            lines = lines.push("data #{String.from_bytes(Bytes.concat(data)).unwrap!.inspect}")
            data = []
          end

          found = try Multipart.disposition(headers)
          lines = lines.push("part #{found.name} #{found.filename.unwrap_or("-")}")

        Multipart.Event.Data(bytes) -> data = data.push(bytes)
        Multipart.Event.Finished ->
          lines = lines.push("data #{String.from_bytes(Bytes.concat(data)).unwrap!.inspect}")
          data = []
          lines = lines.push("end")
      end
    end

    at = at + size
  end

  ok(Told(lines: lines, finished: Multipart.finish(parser).ok?))
end

def kind(event: Multipart.Event) -> String
  case event
    Multipart.Event.Part(headers) -> "part #{headers.size}"
    Multipart.Event.Data(bytes) -> "data #{bytes.size}"
    Multipart.Event.Finished -> "end"
  end
end

# The data of the parts of a body cut into pieces of `size` bytes, joined; an error when the body does not finish.
def data_of(body: Bytes, size: Int) -> Result[Bytes]
  parser = Multipart.start(BOUNDARY)
  data: List[Bytes] = []
  at = 0
  while at < body.size
    step = try Multipart.feed(parser, body.drop(at).take(size))
    parser = step.parser
    for event in step.events
      case event
        Multipart.Event.Data(bytes) -> data = data.push(bytes)
        _ -> next
      end
    end

    at = at + size
  end

  try Multipart.finish(parser)
  ok(Bytes.concat(data))
end

def expected() -> List[String]
  ["part title -", "data \"buy milk\"", "part photo a.txt", "data \"line one\\r\\nline two --XyZ not yet\"", "end"]
end

def main() -> Void
  Test.run([
    Test.test("a body in one piece gives each part, its data and the end") do
      told = try tell(BODY.bytes, 4096)
      try Test.eq(told.lines, expected())
      Test.assert(told.finished, "the last boundary was seen")
    end,
    Test.test("the same events for every cut of the body, even inside a delimiter") do
      for size in [1, 2, 3, 5, 7, 11, 13]
        told = try tell(BODY.bytes, size)
        try Test.eq(told.lines, expected())
      end

      ok()
    end,
    Test.test("a preamble before the first boundary is skipped, and the epilogue after the last") do
      told = try tell("this is a preamble\r\n#{BODY}".bytes, 6)
      Test.eq(told.lines, expected())
    end,
    Test.test("a body that ends before its last boundary is not finished") do
      cut = BODY.slice(0, 60)
      told = try tell(cut.bytes, 8)
      Test.assert(not told.finished, "a cut body is not finished")
    end,
    Test.test("a part with no headers, and a part with empty data") do
      body = "--XyZ\r\n\r\nno headers\r\n--XyZ\r\nContent-Disposition: form-data; name=\"e\"\r\n\r\n\r\n--XyZ--"
      parser = Multipart.start(BOUNDARY)
      step = try Multipart.feed(parser, body.bytes)
      kinds = step.events.map do |event| kind(event) end
      Test.eq(kinds, ["part 0", "data 10", "part 1", "end"])
    end,
    Test.test("text after a boundary on its line, and headers with no colon, are errors") do
      try Test.error?(Multipart.feed(Multipart.start(BOUNDARY), "--XyZ junk\r\n".bytes))
      Test.error?(Multipart.feed(Multipart.start(BOUNDARY), "--XyZ\r\nno colon here\r\n\r\n".bytes))
    end,
    Test.test("headers over 16 KiB are an error, even when they never end") do
      long = "--XyZ\r\nX-Long: #{List.repeat("a", 17_000).join("")}"
      Test.error?(Multipart.feed(Multipart.start(BOUNDARY), long.bytes))
    end,
    Test.test("the boundary of a content type, quoted or not, and the bad ones") do
      try Test.eq(Multipart.boundary("multipart/form-data; boundary=abc"), ok("abc"))
      try Test.eq(Multipart.boundary("Multipart/Form-Data; charset=utf-8; boundary=\"a b'c\""), ok("a b'c"))
      try Test.error?(Multipart.boundary("multipart/form-data"))
      try Test.error?(Multipart.boundary("multipart/mixed; boundary=abc"))
      try Test.error?(Multipart.boundary("multipart/form-data; boundary=\"\""))
      try Test.error?(Multipart.boundary("multipart/form-data; boundary=#{List.repeat("a", 71).join("")}"))
      Test.error?(Multipart.boundary("multipart/form-data; boundary=a;b=\"c\"; boundary=d"))
    end,
    Test.test("the Content-Disposition: name, filename with quotes and semicolons, and the bad ones") do
      field = [
        HTTP.Header(name: "content-disposition", value: "form-data; name=\"a;b\"; filename=\"x \\\"y\\\".txt\""),
      ]

      found = try Multipart.disposition(field)
      try Test.eq(found.name, "a;b")
      try Test.eq(found.filename, some("x \"y\".txt"))
      path = [HTTP.Header(name: "content-disposition", value: "form-data; name=\"f\"; filename=\"C:\\temp\\a.txt\"")]
      raw = (try Multipart.disposition(path)).filename.unwrap_or("")
      try Test.eq(raw, "C:\\temp\\a.txt")
      try Test.eq(Multipart.safe_filename(raw), "a.txt")
      try Test.error?(Multipart.disposition([]))
      try Test.error?(
        Multipart.disposition([HTTP.Header(name: "content-disposition", value: "attachment; name=\"a\"")]),
      )

      Test.error?(
        Multipart.disposition([HTTP.Header(name: "content-disposition", value: "form-data; filename=\"a\"")]),
      )
    end,
    Test.test("the data of a file may hold any byte, the bytes of a delimiter too") do
      every = Bytes.from_list((0..255).to_a).unwrap!
      head = "--XyZ\r\nContent-Disposition: form-data; name=\"f\"; filename=\"b\"\r\n\r\n".bytes
      tail = "\r\n--XyZ--".bytes
      body = Bytes.concat([head, every, "\r\n--XyZ".bytes.take(5), every, tail])
      Test.eq(data_of(body, 7), ok(Bytes.concat([every, "\r\n--XyZ".bytes.take(5), every])))
    end,
    Test.test("safe_filename keeps the last part of a path, no control character and no direction mark") do
      try Test.eq(Multipart.safe_filename("../../etc/passwd"), "passwd")
      try Test.eq(Multipart.safe_filename("C:\\Users\\ana\\photo.png"), "photo.png")
      try Test.eq(Multipart.safe_filename("re#{String.from_code(0)}port\n.pdf"), "report.pdf")
      try Test.eq(Multipart.safe_filename("a#{String.from_code(0x85)}b"), "ab")
      try Test.eq(Multipart.safe_filename("#{String.from_code(0x202E)}gpj.exe"), "gpj.exe")
      try Test.eq(Multipart.safe_filename("x#{String.from_code(0x2066)}#{String.from_code(0x200F)}.txt"), "x.txt")
      try Test.eq(Multipart.safe_filename(".."), "file")
      try Test.eq(Multipart.safe_filename("dir/"), "file")
      Test.eq(Multipart.safe_filename(List.repeat("x", 300).join("")).length, 255)
    end,
  ])
end
