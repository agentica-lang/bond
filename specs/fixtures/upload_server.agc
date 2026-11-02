## The program of `uploads.feature`: an app with `Bond.uploads` (a file of at most 1 KiB, a body of at most 4 KiB) on
## 127.0.0.1 and a free port. It says the port on its first line. `POST /upload` answers with the text fields, then
## for each file of `photo` its field, safe name, type, size and content, and the path where Bond saved it.

import Bond from "../../bond"

LIMITS = Bond.UploadOptions(max_file_bytes: 1_024, max_total_bytes: 4_096)

def hello(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "hello"))
end

def upload(conn: Bond.Conn) -> Result[Bond.Conn]
  fields = try Bond.form_params(conn)
  lines: List[String] = []
  for name in fields.keys
    lines = lines.push("#{name}=#{fields[name].join(",")}")
  end

  for saved in Bond.file_all(conn, "photo")
    file = try File.open(saved.path)
    content = try File.read_bytes(file, 1_024)
    File.close(file)
    text = String.from_bytes(content).unwrap_or("?")
    lines = lines.push("file #{saved.name} #{saved.filename} #{saved.content_type} #{saved.size} #{text}")
    lines = lines.push("path #{saved.path}")
  end

  return ok(Bond.text(conn, 200, lines.join("\n")))
end

def main() -> Void
  app = Bond.app() |> Bond.uploads(LIMITS) |> Bond.get("/hello", &hello) |> Bond.post("/upload", &upload)
  server = Bond.start(app, "127.0.0.1", 0).unwrap!
  puts("listening on #{Bond.local_port(server)}")
  IO.flush()
  Bond.wait(server).unwrap!
end
