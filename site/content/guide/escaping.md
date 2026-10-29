---
title: HTML and escaping
weight: 7
description: Keep a value of the client from becoming markup, with HTML.escape of std/html.
---

# HTML and escaping

`Bond.html` sends the text as it is. If a value that a client sent is put in that text, the client writes part of your page: a name like `<script>...</script>` runs in the browser of everyone who sees the page. That is cross-site scripting (XSS), and the fix is to escape the value.

Bond has no function for this: `HTML.escape` of `std/html` is the one way. It is one import, and a function of Bond with the same job would be a second name for it. `HTML.escape(text)` replaces `&`, `<`, `>`, `"` and `'` with `&amp;`, `&lt;`, `&gt;`, `&quot;` and `&#39;`.

## The pattern

Escape every value that you interpolate into HTML, at the place where you write it, and not before: a value that is escaped early is escaped twice or not at all by the next function that touches it.

```agentica
import HTML from "std/html"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def greet(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.query(conn, "name")
  return ok(Bond.html(conn, 200, "<p>Hello, #{HTML.escape(name)}</p>"))
end

def page_not_found(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.html(conn, 404, "<h1>Nothing at #{HTML.escape(conn.path)}</h1>"))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/greet", &greet) |> Bond.not_found(&page_not_found)
  puts(Testing.request(app, "GET", "/greet?name=Ana", [], "").body)
  puts(Testing.request(app, "GET", "/greet?name=%3Cscript%3Ealert(1)%3C%2Fscript%3E", [], "").body)
  puts(Testing.request(app, "GET", "/greet?name=%22+onmouseover%3D%22x", [], "").body)
  puts(Testing.request(app, "GET", "/<b>", [], "").body)
end
```

```output
<p>Hello, Ana</p>
<p>Hello, &lt;script&gt;alert(1)&lt;/script&gt;</p>
<p>Hello, &quot; onmouseover=&quot;x</p>
<h1>Nothing at /&lt;b&gt;</h1>
```

## What comes from the client

Treat all of these as client text: `Bond.query` and `Bond.form` values, `Bond.param`, the string fields of `Bond.json_body`, `Bond.cookie`, `Bond.request_header`, `conn.path` and `conn.body`. Values from your own database count too when a client wrote them (a comment, a user name): escape at the output, not at the input.

## What `HTML.escape` is for

It is right for text between tags, and for a value inside a quoted attribute (`<input value="#{HTML.escape(value)}">`), since it escapes both kinds of quote. It is not enough in these places, so do not interpolate a client value there at all, or build it with care:

- An attribute without quotes, the text of a `<script>` or `<style>`, or an event attribute such as `onclick`.
- A URL in `href` or `src`: escaping does not stop `javascript:alert(1)`. Check that it starts with `/` or `https://`.
- A JSON value in a page: encode it with `JSON.encode`, and also escape `<` in it, or send it as a `Bond.json` answer.

`HTML.unescape` turns entities back into characters. It is for reading text, not a safety step: never unescape a client value and then put it in a page.

## What Bond writes itself

Bond puts no value of the client into an answer of its own. The 404, the 405 and the 500 have fixed texts, and so has each 400 of `query`, `form` and `json_body` (the name in the text is the one you wrote in the code). They are sent as `text/plain`, which a browser does not show as markup. The message you pass to `Bond.bad_request` is sent as `text/plain` too. The handlers that you give to `Bond.not_found` and `Bond.on_error` are your code, and the rules of this page apply to them: escape `conn.path` as above.

`Bond.redirect` sends no body, and `Bond.static` serves files as they are: a `.html` file of the folder is as safe as you wrote it.
