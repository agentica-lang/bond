## The program of `uploads.feature`: an app with `Bond.uploads` (a file of at most 1 KiB, a text field of at most
## 256 bytes, a body of at most 4 KiB) and `Bond.csrf` on 127.0.0.1 and a free port. It says the port on its first
## line. `POST /upload` answers with the text fields, then for each file of `photo` its field, safe name, type, size and
## content, and the path where Bond saved it. Every answer has `X-Upload-Folders`: how many folders of uploads were
## made for the request, counted in the `dir` of the uploads by an after filter, before Bond removes its folder.

import Bond from "../../bond"

private

LIMITS = Bond.UploadOptions(
  max_file_bytes: 1_024,
  max_field_bytes: 256,
  max_fields_bytes: 1_024,
  max_total_bytes: 4_096,
)

def hello(conn: Bond.Conn) -> Result[Bond.Conn] = ok(Bond.text(conn, 200, "hello"))

def upload(conn: Bond.Conn) -> Result[Bond.Conn]
  fields = try Bond.form_params(conn)
  lines: List[String] = []
  for name in fields.keys
    lines = lines.push("#{name}=#{fields[name].join(",")}")
  end

  for saved in Bond.file_all(conn, "photo")
    file = try File.open(saved.path)
    content = try File.read_bytes(file, 1_024)
    _ = File.close(file)
    text = String.from_bytes(content).unwrap_or("?")
    lines = lines.push("file #{saved.name} #{saved.filename} #{saved.content_type} #{saved.size} #{text}")
    lines = lines.push("path #{saved.path}")
  end

  ok(Bond.text(conn, 200, lines.join("\n")))
end

# The `dir` of the uploads is made at the start, and again by a before filter when a request removed it, and the
# after filter that counts in it removes it, since a scenario has no hook to clean up when the server stops. Being
# made at the start, it is there for the first request even if Bond read a body before the filters.
def make_dir(dir: String, conn: Bond.Conn) -> Result[Bond.Conn]
  _ = Dir.mkdir_private(dir)
  ok(conn)
end

def count_folders(dir: String, conn: Bond.Conn) -> Result[Bond.Conn]
  folders = 0
  case Dir.list(dir)
    ok(names) -> folders = names.size
    error(_) -> folders = 0
  end

  _ = Path.remove(dir)
  ok(Bond.header(conn, "x-upload-folders", folders.to_s))
end

def main() -> Void
  root = System.env("TMPDIR").unwrap_or("/tmp")
  if root == ""
    root = "/tmp"
  end

  dir = Path.join([root, "bond-upload-spec-#{OpenSSL.Random.hex(8)}"]).unwrap!
  Dir.mkdir_private(dir).unwrap!
  routes = (
    Bond.app()
    |> Bond.uploads(LIMITS.with(dir: dir))
    |> Bond.get("/hello", &hello)
  )

  made = routes |> Bond.before() do |conn| make_dir(dir, conn) end
  counted = made |> Bond.after() do |conn| count_folders(dir, conn) end
  app = (
    counted
    |> Bond.csrf()
    |> Bond.post("/upload", &upload)
  )

  server = Bond.start(app, "127.0.0.1", 0).unwrap!
  puts("listening on #{Bond.local_port(server)}")
  IO.flush()
  Bond.wait(server).unwrap!
end
