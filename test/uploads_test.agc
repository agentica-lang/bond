import HTTP from "std/http"
import Bond from "../bond"
import Testing from "../testing"

BOUNDARY = "bond-test-boundary"
CONTENT_TYPE = [Header(name: "content-type", value: "multipart/form-data; boundary=bond-test-boundary")]
LIMITS = Bond.UploadOptions(max_file_bytes: 16, max_total_bytes: 1_024)

# What a handler saw of a form: the text fields, then each file with its content, and whether its file is there.
def show(conn: Bond.Conn) -> Result[Bond.Conn]
  title = try Bond.form(conn, "title")
  tags = try Bond.form_all(conn, "tag")
  lines = ["title=#{title}", "tags=#{tags.join(",")}"]
  for upload in Bond.file_all(conn, "photo")
    file = try File.open(upload.path)
    content = try File.read_bytes(file, 1_024)
    File.close(file)
    lines = lines.push(
      "#{upload.filename} #{upload.content_type} #{upload.size} #{String.from_bytes(content).unwrap!}",
    )
    lines = lines.push("path #{upload.path}")
  end

  return ok(Bond.text(conn, 200, lines.join("\n")))
end

def need_file(conn: Bond.Conn) -> Result[Bond.Conn]
  upload = try Bond.file(conn, "photo")
  return ok(Bond.text(conn, 200, upload.filename))
end

def app() -> Bond.App
  return Bond.app() |> Bond.uploads(LIMITS) |> Bond.post("/show", &show) |> Bond.post("/need", &need_file)
end

def field(name: String, value: String) -> String
  return "--#{BOUNDARY}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
end

def file_part(name: String, filename: String, value: String) -> String
  head = "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{filename}\"\r\nContent-Type: text/plain"
  return "--#{BOUNDARY}\r\n#{head}\r\n\r\n#{value}\r\n"
end

def post(target: String, parts: List[String]) -> HttpResponse
  body = "#{parts.join("")}--#{BOUNDARY}--\r\n"
  return Testing.request_bytes(app(), "POST", target, CONTENT_TYPE, body.bytes)
end

def text(response: HttpResponse) -> String
  return String.from_bytes(response.body).unwrap!
end

def main() -> Void
  Test.run([
    Test.test("the handler gets the fields and the saved files, and the files are removed after") do
      parts = [field("title", "trip"), field("tag", "a"), field("tag", "b"), file_part("photo", "../../x.txt", "hi")]
      response = post("/show", parts)
      try Test.eq(response.status, 200)
      lines = text(response).split("\n")
      try Test.eq(lines.take(3), ["title=trip", "tags=a,b", "x.txt text/plain 2 hi"])
      path = lines[3].slice(5, lines[3].length - 5)
      try Test.assert(not path.include?(".."), "the saved path #{path} has no text of the client")
      try Test.assert(path.end_with?("/4"), "the file is saved under a number")
      Test.error?(File.stat(path))
    end,
    Test.test("a file over max_file_bytes and a body over max_total_bytes are a 413 that closes") do
      big = post(
        "/show",
        [field("title", "t"), field("tag", "a"), file_part("photo", "a.txt", List.repeat("x", 17).join(""))],
      )
      try Test.eq(big.status, 413)
      try Test.eq(HTTP.header_values(big.headers, "connection"), ["close"])
      many = List.repeat(field("tag", List.repeat("y", 100).join("")), 12)
      Test.eq(post("/show", many).status, 413)
    end,
    Test.test("a missing file is a 400 for Bond.file, and an empty file input is no file") do
      try Test.eq(post("/need", [field("title", "t")]).status, 400)
      empty = "--#{BOUNDARY}\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"\"\r\n\r\n\r\n"
      Test.eq(post("/need", [empty]).status, 400)
    end,
    Test.test("a body that is not multipart as RFC 7578 frames it is a 400") do
      try Test.eq(post("/show", ["--#{BOUNDARY} junk\r\n"]).status, 400)
      cut = Testing.request_bytes(app(), "POST", "/show", CONTENT_TYPE, field("title", "t").bytes)
      try Test.eq(cut.status, 400)
      no_boundary = [Header(name: "content-type", value: "multipart/form-data")]
      Test.eq(Testing.request_bytes(app(), "POST", "/show", no_boundary, "".bytes).status, 400)
    end,
    Test.test("a text field that is not UTF-8 is a 400") do
      head = "--#{BOUNDARY}\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\n".bytes
      body = Bytes.concat([head, Bytes.from_list([255, 254]).unwrap!, "\r\n--#{BOUNDARY}--".bytes])
      Test.eq(Testing.request_bytes(app(), "POST", "/show", CONTENT_TYPE, body).status, 400)
    end,
    Test.test("without Bond.uploads a multipart body stays bytes, and Bond.form says it needs uploads") do
      plain = Bond.app() |> Bond.post("/show", &show)
      body = "#{field("title", "t")}--#{BOUNDARY}--".bytes
      response = Testing.request_bytes(plain, "POST", "/show", CONTENT_TYPE, body)
      try Test.eq(response.status, 400)
      Test.eq(text(response), "a multipart/form-data body needs Bond.uploads")
    end,
  ])
end
