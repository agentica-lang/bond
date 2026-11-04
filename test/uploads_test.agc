import HTTP from "std/http"
import Bond from "../bond"
import Testing from "../testing"

BOUNDARY = "bond-test-boundary"
CONTENT_TYPE = [Header(name: "content-type", value: "multipart/form-data; boundary=bond-test-boundary")]
LIMITS = Bond.UploadOptions(max_file_bytes: 16, max_field_bytes: 64, max_fields_bytes: 256, max_total_bytes: 1_024)

# What a handler saw of a form: the text fields, then each file with its content, and whether its file is there.
def show(conn: Bond.Conn) -> Result[Bond.Conn]
  title = try Bond.form(conn, "title")
  tags = try Bond.form_all(conn, "tag")
  lines = ["title=#{title}", "tags=#{tags.join(",")}"]
  for upload in Bond.file_all(conn, "photo")
    file = try File.open(upload.path)
    content = try File.read_bytes(file, 1_024)
    _ = File.close(file)
    lines = lines.push(
      "#{upload.filename} #{upload.content_type} #{upload.size} #{String.from_bytes(content).unwrap!}",
    )

    lines = lines.push("path #{upload.path}")
  end

  return ok(Bond.text(conn, 200, lines.join("\n")))
end

def failing(conn: Bond.Conn) -> Result[Bond.Conn]
  return error("the handler failed")
end

def refuse(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.halt(conn, 403, "refused"))
end

def body_size(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "#{conn.body.size} #{Bond.file_all(conn, "photo").size}"))
end

def need_file(conn: Bond.Conn) -> Result[Bond.Conn]
  upload = try Bond.file(conn, "photo")
  return ok(Bond.text(conn, 200, upload.filename))
end

def app_with(options: Bond.UploadOptions) -> Bond.App
  routes = (
    Bond.app()
    |> Bond.uploads(options)
    |> Bond.post("/show", &show)
    |> Bond.post("/need", &need_file)
  )

  return (
    routes
    |> Bond.post("/fail", &failing)
    |> Bond.get("/size", &body_size)
  )
end

def app() -> Bond.App
  return app_with(LIMITS)
end

def field(name: String, value: String) -> String
  return "--#{BOUNDARY}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
end

def file_part(name: String, filename: String, value: String) -> String
  head = "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{filename}\"\r\nContent-Type: text/plain"
  return "--#{BOUNDARY}\r\n#{head}\r\n\r\n#{value}\r\n"
end

def post(target: String, parts: List[String]) -> HttpResponse
  return post_to(app(), target, parts)
end

def post_to(served: Bond.App, target: String, parts: List[String]) -> HttpResponse
  body = "#{parts.join("")}--#{BOUNDARY}--\r\n"
  return Testing.request_bytes(served, "POST", target, CONTENT_TYPE, body.bytes)
end

# A new empty folder for the uploads of one test, under the temporary folder of the system.
def scratch() -> Result[String]
  root = System.env("TMPDIR").unwrap_or("/tmp")
  if root == ""
    root = "/tmp"
  end

  dir = try Path.join([root, "bond-uploads-test-#{SecureRandom.hex(8)}"])
  try Dir.mkdir_private(dir)
  return ok(dir)
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
      try Test.assert(path.end_with?("/1"), "the first file is saved as 1")
      Test.error?(File.stat(path))
    end,
    Test.test("a file over max_file_bytes and a body over max_total_bytes are a 413 that closes") do
      big = post(
        "/show",
        [field("title", "t"), field("tag", "a"), file_part("photo", "a.txt", List.repeat("x", 17).join(""))],
      )

      try Test.eq(big.status, 413)
      try Test.eq(HTTP.header_values(big.headers, "connection"), ["close"])
      try Test.eq(post("/show", [file_part("photo", "a.txt", "x"), field("title", "t")]).status, 200)
      files = List.repeat(file_part("photo", "a.txt", List.repeat("x", 16).join("")), 12)
      Test.eq(post("/show", files).status, 413)
    end,
    Test.test("a text field over max_field_bytes and the text fields over max_fields_bytes are a 413") do
      try Test.eq(post("/show", [field("title", List.repeat("y", 64).join(""))]).status, 200)
      try Test.eq(post("/show", [field("title", List.repeat("y", 65).join(""))]).status, 413)
      fields = List.repeat(field("tag", List.repeat("y", 60).join("")), 5)
      Test.eq(post("/show", fields).status, 413)
    end,
    Test.test("more than 1000 parts is a 413") do
      roomy = app_with(LIMITS.with(max_fields_bytes: 4_096, max_total_bytes: 1_048_576))
      try Test.eq(post_to(roomy, "/show", List.repeat(field("tag", "a"), 999).push(field("title", "t"))).status, 200)
      Test.eq(post_to(roomy, "/show", List.repeat(field("tag", "a"), 1_001)).status, 413)
    end,
    Test.test("the folder of the uploads is empty after a 413 and after a handler error") do
      dir = try scratch()
      served = app_with(LIMITS.with(dir: dir))
      big = post_to(served, "/show", [file_part("photo", "a.txt", List.repeat("x", 17).join(""))]).status
      after_big = Dir.list(dir)
      failed = post_to(served, "/fail", [file_part("photo", "a.txt", "hi")]).status
      after_failed = Dir.list(dir)
      _ = Path.remove(dir)
      try Test.eq([big, failed], [413, 500])
      try Test.eq(after_big.unwrap_or(["?"]), [])
      Test.eq(after_failed.unwrap_or(["?"]), [])
    end,
    Test.test("a body is not read when a before filter halts, the path has no route or the method is GET") do
      broken = [Header(name: "content-type", value: "multipart/form-data; boundary=bond-test-boundary")]
      junk = "--#{BOUNDARY} junk\r\n".bytes
      try Test.eq(Testing.request_bytes(app(), "POST", "/show", broken, junk).status, 400)
      try Test.eq(Testing.request_bytes(app(), "POST", "/nothing", broken, junk).status, 404)
      try Test.eq(Testing.request_bytes(app(), "GET", "/show", broken, junk).status, 405)
      guarded = app() |> Bond.before(&refuse)
      try Test.eq(Testing.request_bytes(guarded, "POST", "/show", broken, junk).status, 403)
      # A GET is no upload: its body stays in `conn.body`.
      Test.eq(text(Testing.request_bytes(app(), "GET", "/size", broken, junk)), "#{junk.size} 0")
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
      Test.eq(
        text(response),
        "a multipart/form-data body is read by Bond.uploads for the handler, after the before filters",
      )
    end,
  ])
end
