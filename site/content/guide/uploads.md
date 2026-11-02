---
title: Uploads
weight: 18
description: Read a multipart/form-data form with files, saved to disk as they arrive, with size caps.
---

# Uploads

A form with a file (`<form method="post" enctype="multipart/form-data">` and an `<input type="file">`) sends a `multipart/form-data` body. `Bond.uploads(app, options)` reads it as it arrives, before the filters run:

- each file goes to disk, in a new private folder for the request, under a name of Bond's own;
- the text fields go to [`Bond.form`, `Bond.form_all`, `Bond.form_int` and `Bond.form_params`](/guide/query/#forms), as for a plain form;
- `Bond.file(conn, name)` gives the first file of a field (a 400 when there is none), and `Bond.file_all(conn, name)` every file of it (`<input type="file" multiple>`).

A file is a `Bond.UploadedFile`:

- `name`: the field;
- `filename`: the name the client gave, made safe to show: the part after the last `/` or `\`, with no control character, at most 255 characters, and `file` for an empty name, `.` or `..`;
- `content_type`: the type the client said, `application/octet-stream` when it said none;
- `path`: where Bond saved it;
- `size`: its size in bytes.

```agentica
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
  headers = [Header(name: "content-type", value: "multipart/form-data; boundary=#{boundary}")]
  response = Testing.request_bytes(app, "POST", "/photos", headers, body.bytes)
  puts(response.status)
  puts(Testing.text(response).unwrap!)
end
```

```output
201
beach: me.png, image/png, 6 bytes
```

## The client's filename is not a path

`filename` is only for showing. Never build a path from it, nor trust `content_type`: check the content of the file. Bond saves each file as a number in a folder that only the program can use, named with 16 random bytes, under `options.dir` (the temporary folder of the system by default: `TMPDIR`, `TEMP` or `TMP`, else `/tmp`).

## The files are removed after the answer

When the handler and the filters are done, Bond removes the folder and every file in it, also when a filter or the handler failed. The body is read before the filters run, so a filter that refuses the request (`Bond.csrf`, a login check) runs after the files are saved, and they are removed with its answer; the caps bound what such a request can write. To keep a file, move it with `Path.rename` (same file system) or copy it in the handler. A streamed answer is sent after the files are removed, so do not stream an uploaded file back.

## Limits

`Bond.UploadOptions` has the caps:

- `max_file_bytes` (10 MiB by default): a file over it is a 413;
- `max_total_bytes` (50 MiB by default, at most 256 MiB): a body over it, its fields, files and framing, is a 413;
- `dir`: the folder for the files (see above).

A 413 has `Connection: close`, the rest of the body is not read, the handler does not run and the files already saved are removed. A body that is not `multipart/form-data` as RFC 7578 frames it (no boundary, a part with no name, a cut body, headers of a part over 16 KiB, a text field that is not UTF-8, more than 1000 parts) is a 400.

The server takes a `multipart/form-data` body up to `max_total_bytes`; the other bodies keep `max_body_bytes` of [`Bond.start_with`](/guide/server/#options) (1 MiB by default), so a big upload limit does not make every route read big bodies.

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

Without `Bond.uploads`, a `multipart/form-data` body is read whole into `conn.body` like any other, and `Bond.form` answers it with a 400 that says it needs `Bond.uploads`.

## Testing

`Testing.request_bytes` reads a `multipart/form-data` body the way the server does, in pieces of 64 KiB: the handler gets the files, the limits give the same 413, and the files are removed after the answer.
