---
title: Bond
---

# Bond

```agentica
import Bond from "pkg/bond/bond"

def main() -> Void
  puts(Bond.nothing_like_this())
end
```

```agentica
import Bond from "pkg/bond/bond"
import Testing from "pkg/bond/testing"

def main() -> Void
  app = Bond.app() |> Bond.get("/hello") do |conn| ok(Bond.text(conn, 200, "hello")) end
  puts(Testing.request(app, "GET", "/hello", [], "").body)
end
```
