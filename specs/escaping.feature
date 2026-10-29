Feature: HTML escaping
  `Bond.html` sends the text as it is, so a handler escapes what a client sent with `HTML.escape` of `std/html`
  before it goes into the text. Bond never puts a value of the client into an answer of its own: the 404, the 405 and
  the 400 have fixed texts, as plain text. The app of `specs/fixtures/app.agc` has `/greet`, which follows the guide,
  and a `not_found` handler that shows the path.

  Scenario Outline: A value of the client is escaped in the HTML of a handler (<why>)
    Given the todo app
    When I send "GET" to "/greet?name=<name>"
    Then the status is 200
    And the header "content-type" is "text/html; charset=utf-8"
    And the body is "<body>"

    Examples:
      | why          | name                         | body                                         |
      | a name       | Ana                          | <p>Hello, Ana</p>                            |
      | a script     | %3Cscript%3Ex%3C%2Fscript%3E | <p>Hello, &lt;script&gt;x&lt;/script&gt;</p> |
      | quotes       | %22a%22+%27b%27              | <p>Hello, &quot;a&quot; &#39;b&#39;</p>      |
      | an ampersand | a%26lt%3B                    | <p>Hello, a&amp;lt;</p>                      |

  Scenario: The path in the page of a not found handler is escaped
    Given the todo app with custom handlers
    When I send "GET" to "/<b>x</b>"
    Then the status is 404
    And the body is "<h1>No page at /&lt;b&gt;x&lt;/b&gt;</h1>"

  Scenario Outline: The answers of Bond itself have a fixed text and no value of the client (<why>)
    Given the todo app
    When I send "<method>" to "<path>"
    Then the status is <status>
    And the header "content-type" is "text/plain; charset=utf-8"
    And the body is "<body>"

    Examples:
      | why                          | method | path           | status | body                  |
      | a path with no route         | GET    | /%3Cscript%3E  | 404    | not found             |
      | a method not allowed         | POST   | /hello         | 405    | method not allowed    |
      | a param that is not a number | GET    | /todos/%3Cb%3E | 400    | id must be an integer |
