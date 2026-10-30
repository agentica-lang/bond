---
title: Getting started
weight: 1
description: Add Bond to a project, write a first app and run it.
---

## Install

Install [Agentica](https://agentica-lang.github.io/agentica/getting-started/) 0.19.0-beta.1 or later. Bond is a package: you add it to the `agentica.toml` of your project as a dependency on its git repository.

Pin a release by its tag (Bond 0.2.0 needs Agentica 0.19.0-beta.1 or later, 0.1.0 needs 0.16.0 or later):

```sh
agentica add bond https://github.com/agentica-lang/bond --tag 0.2.0
```

This writes the dependency in `agentica.toml` and `agentica.lock`, and puts the files of Bond in `deps/bond/`. For a manifest you edited by hand, run `agentica install`.

```toml
[dependencies]
bond = { git = "https://github.com/agentica-lang/bond", tag = "0.2.0" }
```

Then import it from your program with `pkg/bond/bond`.

## A first app

An app starts with `Bond.app()`. Each `Bond.get`, `Bond.post` and so on takes the app, a path pattern and a handler, and gives the app back, so they chain with `|>`. A handler is a function that takes a `Conn` and gives `ok(conn)` with the answer in it.

The app does not hold your state. A handler that needs a store gets it from a closure: write it as a block, as `show` does below. That is simpler than making the app generic over the state.

```agentica
import Bond from "pkg/bond/bond"

struct Store
  names: ATS[String, String]
end

def show(store: Store, conn: Bond.Conn) -> Result[Bond.Conn]
  id = try Bond.param(conn, "id")
  case store.names.get(id)
    ok(name) -> return ok(Bond.text(conn, 200, name))
    error(_) -> return ok(Bond.halt(conn, 404, "no such name"))
  end
end

def main() -> Void
  store = Store(names: ATS.new())
  store.names.put("1", "Ada")
  app = (
    Bond.app()
    |> Bond.before(&Bond.log_request)
    |> Bond.get("/names/:id") do |conn| show(store, conn) end
  )
  Bond.run(app, "127.0.0.1", 4567).unwrap!
end
```

## Run it

`Bond.run` serves the app with the HTTP server of `std/http` and returns when the server closes. Save the program as `app.agc` and run it:

```sh
agentica app.agc
curl http://127.0.0.1:4567/names/1
```

The full todo list program is [examples/todos.agc](https://github.com/agentica-lang/bond/blob/main/examples/todos.agc). It keeps its todos in an `ATS` table and takes the ids from `ATS.add(key, n)`, which is atomic. To try an app without a socket, see [Testing](/guide/testing/).
