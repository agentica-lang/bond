---
title: Uploads
weight: 18
description: Read a multipart/form-data form with files, saved to disk as they arrive, with size caps.
---

# Uploads

A form with a file (`<form method="post" enctype="multipart/form-data">` and an `<input type="file">`) sends a `multipart/form-data` body. `Bond.uploads(app, options)` reads it as it arrives, after the before filters and before the handler:

- each file goes to disk, in a new private folder for the request, under a name of Bond's own;
- the text fields go to [`Bond.form`, `Bond.form_all`, `Bond.form_int` and `Bond.form_params`](/guide/query/#forms), as for a plain form;
- `Bond.file(conn, name)` gives the first file of a field (a 400 when there is none), and `Bond.file_all(conn, name)` every file of it (`<input type="file" multiple>`).

A file is a `Bond.UploadedFile`:

- `name`: the field;
- `filename`: the name the client gave, made safe to show: the part after the last `/` or `\`, with no control character and no mark that turns the direction of the text, at most 255 characters, and `file` for an empty name, `.` or `..`;
- `content_type`: the type the client said, `application/octet-stream` when it said none;
- `path`: where Bond saved it;
- `size`: its size in bytes.

```agentica
import HTTP from "std/http"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def save(conn: Bond.Conn) -> Result[Bond.Conn]
  title = try Bond.form(conn, "title")
  photo = try Bond.file(conn, "photo")
  return ok(Bond.text(conn, 201, "#{title}: #{photo.filename}, #{photo.content_type}, #{photo.size} bytes"))
end

def main() -> Void
  app = Bond.app() |> Bond.uploads() |> Bond.post("/photos", &save)
  boundary = "XyZ"
  body = [
    "--XyZ\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nbeach\r\n",
    "--XyZ\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"../me.png\"\r\n",
    "Content-Type: image/png\r\n\r\nPNG...\r\n--XyZ--\r\n",
  ].join("")
  headers = [HTTP.Header(name: "content-type", value: "multipart/form-data; boundary=#{boundary}")]
  response = Testing.request_bytes(app, "POST", "/photos", headers, body.bytes)
  puts(response.status)
  puts(Testing.text(response).unwrap!)
end
```

```output
201
beach: me.png, image/png, 6 bytes
```

## When the body is read

The before filters run first, then Bond finds the route. A filter that halts (`Bond.csrf`, a login check), a path with no route (404) and a method with no route (405) are answered without reading the body, so a refused request writes nothing to disk; the server closes the connection after such an answer. Only then does Bond read the body, put the form in the conn and run the handler, so a before filter sees no form (`Bond.form` there is the same 400 as without `Bond.uploads`). Only a POST, PUT or PATCH is an upload: a GET or a DELETE with a `multipart/form-data` body keeps the server's body limit, and its body stays in `conn.body`. A refusal of the body (a 413 or a 400) halts the conn, so the handler does not run, and the after filters see it like any other answer.

## The client's filename is not a path

`filename` is only for showing. Never build a path from it, nor trust `content_type`: check the content of the file. Bond saves the files as 1, 2, 3 in a folder that only the program can use, named with 16 random bytes, under `options.dir` (the temporary folder of the system by default: `TMPDIR`, `TEMP` or `TMP`, else `/tmp`). The folder is made for the first file, so a form of text fields makes none.

## The files are removed after the answer

When the handler and the after filters are done, Bond removes the folder and every file in it, also when the handler failed or the body was refused. To keep a file, move it with `Path.rename` (same file system) or copy it in the handler. A streamed answer is sent after the files are removed, so do not stream an uploaded file back.

## Limits

`Bond.UploadOptions` has the caps:

- `max_file_bytes` (10 MiB by default): a file over it is a 413;
- `max_field_bytes` (1 MiB by default): a text field over it is a 413, since a text field is held in memory;
- `max_fields_bytes` (2 MiB by default): all the text fields together over it is a 413;
- `max_total_bytes` (50 MiB by default, at most 256 MiB): a body over it, its fields, files and framing, is a 413;
- `dir`: the folder for the files (see above); it must exist, or each file is a 500.

Each cap is 1 or more, `max_file_bytes` is at most `max_total_bytes` and `max_field_bytes` at most `max_fields_bytes`, or the program stops at `Bond.uploads`. More than 1000 parts is a 413 too. A 413 has `Connection: close`, the rest of the body is not read, the handler does not run and the files already saved are removed. A body that is not `multipart/form-data` as RFC 7578 frames it (no boundary, a part with no name, a cut body, headers of a part over 16 KiB, a text field that is not UTF-8) is a 400.

The server waits at most `request_timeout_ms` of [`Bond.start_with`](/guide/server/#options) (30 seconds by default) for each read of the body: a client that sends nothing for that long ends its upload, and a slow link that keeps sending is not cut. The server takes a `multipart/form-data` body up to `max_total_bytes`; other bodies keep `max_body_bytes` (1 MiB by default), so a big upload limit does not make every route read big bodies.

```agentica
import Bond from "pkg/bond/bond"

# The id is a number (`param_int`), so the new path has no text of the client in it.
def avatar(conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param_int(conn, "id")
  image = try Bond.file(conn, "avatar")
  try Path.rename(image.path, "avatars/#{id}")
  return ok(Bond.redirect(conn, "/users/#{id}", 303))
end

def main() -> Void
  limits = Bond.UploadOptions(max_file_bytes: 2_097_152, max_total_bytes: 4_194_304)
  app = Bond.app() |> Bond.uploads(limits) |> Bond.post("/users/:id/avatar", &avatar)
  Bond.run(app, "127.0.0.1", 4567).unwrap!
end
```

Without `Bond.uploads`, a `multipart/form-data` body is read whole into `conn.body` like any other, and `Bond.form` answers it with a 400: `a multipart/form-data body is read by Bond.uploads for the handler, after the before filters`.

## Testing

`Testing.request_bytes` reads a `multipart/form-data` body as the server does, in pieces of 64 KiB and after the before filters: the handler gets the files, the limits give the same 413, and the files are removed after the answer.
