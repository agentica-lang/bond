## Runs an app in process, with no socket: the request goes through the same filters and routes as one that came
## over `Bond.run`.
##
## ```ruby
## import Testing from "pkg/bond/testing"
##
## response = Testing.request(app, "POST", "/todos", [], "buy milk")
## ```

import Apps from "src/app"
import {App} from "src/app"

## Sends the request to `app` and gives the response. `target` is the path with its query, as a client sends it
## (`/todos?done=1`); header names are lowercased, as the server does.
export def request(app: App, method: String, target: String, headers: List[Header], body: String) -> HttpResponse
  path = target
  case target.index_of("?")
    ok(at) -> path = target.slice(0, at)
    error(_) -> path = target
  end

  lowered = headers.map do |header| Header(name: header.name.downcase, value: header.value) end
  return Apps.handle(app, HttpRequest(method: method, target: target, path: path, headers: lowered, body: body))
end
