---
title: Views
weight: 16
description: Pages from EAG templates, with partials and a layout, as plain functions that return a String.
---

# Views

A view is a function that returns a `String`. A page is a view, a partial is a view that a page calls, and a layout is a view that takes the HTML of the page. There is no view API in Bond: the pieces are an [EAG template](/guide/escaping/#templates), `Bond.escape` and `Bond.html`, and the rest is calling functions.

Every view starts with `<%@ escape &Bond.escape %>`, so each `<%= %>` is escaped. The checker types the arguments and every tag: a mistyped field in a template is an error before the program runs.

```agentica
import EAG from "std/eag"
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

struct Message
  author: String
  text: String
end

def message(m: Message) -> String
  return <<~EAG
    <%@ escape &Bond.escape %>
    <li class='message'><b><%= m.author %></b>: <%= m.text %></li>
  EAG
end

def room(name: String, messages: List[Message]) -> String
  return <<~EAG
    <%@ escape &Bond.escape %>
    <h1><%= name %></h1>
    <ul>
    <% for m in messages %>
    <%== message(m) -%>
    <% end %>
    </ul>
  EAG
end

def layout(title: String, inner: String) -> String
  return <<~EAG
    <%@ escape &Bond.escape %>
    <title><%= title %></title>
    <main>
    <%== inner -%>
    </main>
  EAG
end

def show_room(conn: Bond.Conn) -> Result[Bond.Conn]
  name = try Bond.query(conn, "name")
  messages = [Message(author: "Ana", text: "hello"), Message(author: name, text: "<script>1</script>")]
  return ok(Bond.html(conn, 200, layout(name, room(name, messages))))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/room", &show_room)
  puts(Testing.text(Testing.request(app, "GET", "/room?name=%3Ci%3EDev%3C%2Fi%3E")).unwrap!)
end
```

```output
<title>&lt;i&gt;Dev&lt;/i&gt;</title>
<main>
<h1>&lt;i&gt;Dev&lt;/i&gt;</h1>
<ul>
<li class='message'><b>Ana</b>: hello</li>
<li class='message'><b>&lt;i&gt;Dev&lt;/i&gt;</b>: &lt;script&gt;1&lt;/script&gt;</li>
</ul>
</main>

```

## Partials and the layout

A partial is a function like `message` above. A page puts its result in with `<%== %>`, and a loop is a `for` in a tag (`<% for m in messages %>`). A partial sees only what the page passes it. The handler renders the page first and gives it to the layout: `layout(name, room(name, messages))`.

## `<%==` takes only your own HTML

The result of a view is already escaped, so a layout or a page inserts it with `<%==` (with `<%=` it would be escaped twice). Never put a value of a client in a `<%==`. Nothing checks this, since a `String` is a `String`: `layout(title, name)` type-checks but is wrong (`name` came from the client and is inserted raw), while `layout(title, room(name, messages))` is right, because `room` escapes `name` first.

A view without `<%@ escape &Bond.escape %>` on its first line escapes nothing, and the checker does not warn. Test each view with a value like `<script>`, as `specs/views.feature` does for the page of the sample.

`-%>` after a `<%==` that inserts a view takes away the line break that the view ends with, so the page has no blank line there.

## Where to put views

A view of an app can sit in its own file (`views/rooms.agc`) with an `export def` for each page. The views file has its own `import EAG from "std/eag"` and `import Bond from "pkg/bond/bond"` (without them its templates are `CHECK-EAG-IMPORT` and `&Bond.escape` is `CHECK-UNKNOWN-NAME`). The file of the handlers imports it with `import Rooms from "views/rooms"` and calls `Rooms.show(...)`. An import is relative to the file that writes it: from a file in a subfolder, such as `handlers/rooms.agc`, it is `"../views/rooms"`.
