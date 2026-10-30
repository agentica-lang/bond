# Bond

A small web framework for [Agentica](https://github.com/agentica-lang/agentica), in the spirit of Sinatra.
Version 0.1.0 has the router, filters, custom handlers, JSON bodies, query strings and forms, cookies, static files, and the helpers to answer.
Limits: static files are text only until Agentica has bodies of bytes, and WebSockets come later (see
[the design](https://github.com/agentica-lang/bond/issues/1)).

Bond 0.1.0 needs Agentica 0.16.0 or later; the next release needs Agentica 0.19.0-beta.1 or later.

Documentation: https://agentica-lang.github.io/bond/

## Install

In your `agentica.toml`:

```toml
[dependencies]
bond = { git = "https://github.com/agentica-lang/bond", tag = "0.1.0" }
```

Or run `agentica add bond https://github.com/agentica-lang/bond --tag 0.1.0`. Both (and `agentica install` for a
manifest you edited) write `agentica.lock` and `deps/bond/`.

## Example

```ruby
import Bond from "pkg/bond/bond"

def hello(conn: Bond.Conn) -> Result[Bond.Conn]
  return ok(Bond.text(conn, 200, "hello"))
end

def main() -> Void
  app = Bond.app() |> Bond.get("/hello", &hello)
  Bond.run(app, "127.0.0.1", 4567).unwrap!
end
```

## Development

The tests are BDD first: the behavior is a Gherkin scenario in `specs/*.feature`, run by `agentica test`. The steps
(`specs/steps.agc`) drive the app of `specs/fixtures/app.agc` through `Testing.request`; only `server.feature` opens
a socket, on 127.0.0.1 and a free port. `test/` has the unit test of the route pattern matcher.

```sh
agentica check   # every .agc file of the package
agentica test
```

`agentica test --only TEXT` runs the scenarios whose name contains `TEXT`. CI pins the Agentica release in
`.github/workflows/ci.yml` (`AGENTICA_VERSION`, with its sha256).

## License

Apache License 2.0. See [LICENSE](LICENSE).
