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
  puts(Testing.text(Testing.request(app, "GET", "/greet?name=Ana")).unwrap!)
  puts(Testing.text(Testing.request(app, "GET", "/greet?name=%3Cscript%3Ealert(1)%3C%2Fscript%3E")).unwrap!)
  puts(Testing.text(Testing.request(app, "GET", "/greet?name=%22+onmouseover%3D%22x")).unwrap!)
  puts(Testing.text(Testing.request(app, "GET", "/<b>")).unwrap!)
end
```

```output
<p>Hello, Ana</p>
<p>Hello, &lt;script&gt;alert(1)&lt;/script&gt;</p>
<p>Hello, &quot; onmouseover=&quot;x</p>
<h1>Nothing at /&lt;b&gt;</h1>
```

## What comes from the client

Treat every value that comes from the query, form, cookie and JSON readers as client text, the maps and lists too: `Bond.query`, `query_all` and `query_params`, `Bond.form` and its relatives, `Bond.cookie` and `Bond.cookies`, and every string in a struct from `Bond.json_body`. So are `Bond.param`, `Bond.request_header` and `conn.body`. `conn.path` is the raw path as the client sent it, not decoded and not checked, so escape it too (the `not_found` handler above does). Values from your own database count when a client wrote them (a comment, a user name): escape at the output, not at the input.

## What `HTML.escape` is for

It is right for text between tags, and for a value inside a quoted attribute (`<input value="#{HTML.escape(value)}">`), since it escapes both kinds of quote. It is not enough in the places below.

- **An attribute without quotes, or the text of a `<style>`:** do not put a client value there.
- **An event attribute such as `onclick`:** the HTML parser decodes `&#39;` back to `'` before the JavaScript runs, so an escaped value still ends the string in the script. Never interpolate a client value into an event handler: put it in a `data-` attribute and read it from a script.
- **A URL in `href` or `src`, or in a redirect:** escaping does not stop `javascript:alert(1)`. A local URL starts with `/`, and its second character is not `/` or `\`, or `//evil.com` and `/\evil.com` go to another site. No control character may be in it either, since a browser drops a tab or a newline inside a URL. Otherwise accept only an `https://` address that your app allows. Still escape the value in the quoted attribute.
- **`Bond.redirect(conn, to)`:** it passes `//evil.com`, `/\evil.com` and `javascript:` through, so check a target that a client gave (`?next=...`) with the same rule first: see [Redirects](/guide/conn/#redirects).
- **JSON in a page:** `HTML.escape` is wrong inside a `<script>`, which does not decode entities. Encode the value with `JSON.encode(JSON.from(value))` and replace `<` with `\u003c`, so `</script>` cannot end the script. In a `data-x="..."` attribute, use `HTML.escape(JSON.encode(JSON.from(value)))`.

```agentica
import HTML from "std/html"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def local_url?(target: String) -> Bool
  if not target.start_with?("/")
    return false
  end

  second = target.slice(1, 1)
  if second == "/" or second == "\\"
    return false
  end

  controls = target.split("").select do |ch| ch.code < 32 end
  return controls.empty?
end

def script_json(value: String) -> String
  return JSON.encode(JSON.from(value)).replace("<", "\\u003c")
end

def go(conn: Bond.Conn) -> Result[Bond.Conn]
  target = Bond.query(conn, "next").unwrap_or("/")
  if not local_url?(target)
    return ok(Bond.redirect(conn, "/"))
  end

  return ok(Bond.redirect(conn, target))
end

def page(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.query(conn, "name")
  link = Bond.query(conn, "next").unwrap_or("/")
  body = "<script>var name = #{script_json(name)};</script>"
  data = "<p data-name=\"#{HTML.escape(JSON.encode(JSON.from(name)))}\"></p>"
  anchor = "<a href=\"#{HTML.escape(link)}\">next</a>"
  return ok(Bond.html(conn, 200, "#{body}\n#{data}\n#{anchor}"))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/go", &go) |> Bond.get("/page", &page)
  for target in ["/done", "//evil.com", "%2F%5Cevil.com", "javascript:alert(1)"]
    response = Testing.request(app, "GET", "/go?next=#{target}")
    puts("#{target} #{response.headers.select do |h| h.name == "location" end.map do |h| h.value end}")
  end
  puts(Testing.text(Testing.request(app, "GET", "/page?name=%3C%2Fscript%3E%22&next=%22%3E")).unwrap!)
end
```

```output
/done ["/done"]
//evil.com ["/"]
%2F%5Cevil.com ["/"]
javascript:alert(1) ["/"]
<script>var name = "\u003c/script>\"";</script>
<p data-name="&quot;&lt;/script&gt;\&quot;&quot;"></p>
<a href="&quot;&gt;">next</a>
```

`HTML.unescape` turns entities back into characters. It is for reading text, not a safety step: never unescape a client value and then put it in a page.

## What Bond writes itself

Bond puts no value of the client into an answer of its own. The 404, the 405 and the 500 have fixed texts, and so has each 400 of `query`, `form` and `json_body` (the name in the text is the one you wrote in the code). They are sent as `text/plain`, which a browser does not show as markup. The message you pass to `Bond.bad_request` is sent as `text/plain` too. The handlers that you give to `Bond.not_found` and `Bond.on_error` are your code, and the rules of this page apply to them: escape `conn.path` as above.

`Bond.redirect` sends no body, and `Bond.static` serves files as they are: a `.html` file of the folder is as safe as you wrote it.
