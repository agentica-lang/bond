# Bond

A small web framework for [Agentica](https://github.com/agentica-lang/agentica), in the spirit of Sinatra.
Version 0.7.0 has the router, filters, JSON bodies, forms, cookies, signed sessions, a cross-site request check, static files with an in-memory cache, gzip, conditional requests and ranges, streaming, WebSockets, file uploads, HTML escaping, views, the client address, per-request assigns and an in-process test helper.

Bond 0.7.0 needs Agentica 0.22.0 or later; the [changelog](CHANGELOG.md) has the version each release needs.

Documentation: https://agentica-lang.github.io/bond/

## Install

In your `agentica.toml`:

```toml
[dependencies]
bond = { git = "https://github.com/agentica-lang/bond", tag = "0.7.0" }
```

Or run `agentica add bond https://github.com/agentica-lang/bond --tag 0.7.0`. Both (and `agentica install` for a
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
(`specs/steps.agc`) drive the app of `specs/fixtures/app.agc` through `Testing.request`; only `server.feature`,
`websocket.feature` and `uploads.feature` open a socket, on 127.0.0.1 and a free port. `test/` has the unit tests,
such as those of the route pattern matcher and the multipart parser.

```sh
agentica check   # every .agc file of the package
agentica fmt --check   # the same files; `agentica fmt` rewrites them (`make fmt-check`)
agentica test --jobs 4   # up to 4 files at once (`make test`, `JOBS=N` sets it)
```

Developing Bond needs Agentica 0.24.1 or later (`agentica test --jobs`); using Bond still needs only 0.22.0.
`agentica test --only TEXT` runs the scenarios whose name contains `TEXT`. CI pins the Agentica release in
`.github/workflows/ci.yml` (`AGENTICA_VERSION`, with its sha256).

## License

Apache License 2.0. See [LICENSE](LICENSE).
