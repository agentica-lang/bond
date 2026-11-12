# Bond

A small web framework for [Agentica](https://github.com/agentica-lang/agentica), in the spirit of Sinatra: a router, filters, JSON and form bodies, cookies, signed sessions, static files, streaming, WebSockets, uploads, views and an in-process test helper.

Documentation: https://agentica-lang.github.io/bond/

## Install

Bond needs Agentica 0.30.0 or later; the [changelog](CHANGELOG.md) has the version each release needs. In your `agentica.toml`:

```toml
[dependencies]
bond = { git = "https://github.com/agentica-lang/bond", tag = "0.11.0" }
```

Or run `agentica add bond https://github.com/agentica-lang/bond --tag 0.11.0`. Both write `agentica.lock` and `deps/bond/` (`agentica install` does it for a manifest you edited).

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

The tests are BDD first: each behavior is a Gherkin scenario in `specs/*.feature`, driven through `Testing.request` by `specs/steps.agc` (only `server`, `websocket` and `uploads` open a socket). `test/` has the unit tests, such as the route pattern matcher and the multipart parser.

```sh
agentica check          # every .agc file of the package
agentica fmt --check    # `agentica fmt` rewrites them
agentica test --jobs 4  # up to 4 files at once
```

`make check`, `make fmt-check` and `make test` run them, and `agentica test --only TEXT` runs the scenarios whose name contains `TEXT`. Developing Bond needs Agentica 0.30.0 or later; CI pins its release in `.github/workflows/ci.yml`.

## License

Apache License 2.0. See [LICENSE](LICENSE).
