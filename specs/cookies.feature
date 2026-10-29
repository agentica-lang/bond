Feature: Cookies
  `Bond.cookies(conn)` is the `Cookie` header read once into a map, and `Bond.cookie(conn, name)` is one value (an
  error when the cookie is not there: it is not an error of the client, so it is a plain `error`, and `unwrap_or`
  gives a default). Values are as the client sent them: not decoded. `Bond.set_cookie(conn, name, value)` adds a
  `Set-Cookie` header with the defaults of Bond: `Path=/`, `HttpOnly` and `SameSite=Lax`. `Bond.set_cookie_with`
  takes a `Cookie.Cookie` of `std/cookie` with every attribute, and `Bond.delete_cookie` deletes a cookie. Each cookie
  is a header of its own: they are never joined. A name or value that `std/cookie` refuses is a mistake of the
  program, so a 500. `GET /whoami`, `/login`, `/logout` and the other routes of `specs/fixtures/app.agc` use them.

  Background:
    Given the todo app

  Scenario: The cookies of the request are read
    When I send "GET" to "/whoami" with the cookie "sid=abc; theme=dark"
    Then the status is 200
    And the body is "sid=abc theme=dark"

  Scenario: A cookie that is not there is an error that unwrap_or answers
    When I send "GET" to "/whoami"
    Then the body is "sid=none theme=none"

  Scenario: Values are not decoded and the first of a name wins
    When I send "GET" to "/whoami" with the cookie "sid=a%20b; sid=2; theme=x"
    Then the body is "sid=a%20b theme=x"

  Scenario: More than one Cookie header is read as one
    When I send "GET" to "/whoami" with the cookies "sid=abc" and "theme=dark"
    Then the body is "sid=abc theme=dark"

  Scenario: A cookie is set with the defaults of Bond
    When I send "GET" to "/login"
    Then the status is 200
    And the header "set-cookie" has the value "sid=abc123; Path=/; HttpOnly; SameSite=Lax"

  Scenario: Every attribute can be set and each cookie is a header of its own
    When I send "GET" to "/login"
    Then the header "set-cookie" appears 3 times
    And the header "set-cookie" has the value:
      """
      theme=dark; Domain=example.com; Path=/app; Max-Age=3600; Secure; SameSite=None
      """
    And the header "set-cookie" has the value:
      """
      pref=wide; Expires=Wed, 21 Oct 2015 07:28:00 GMT; HttpOnly
      """

  Scenario: A cookie set before a redirect is sent with it
    When I send "GET" to "/login-redirect"
    Then the status is 302
    And the header "location" is "/whoami"
    And the header "set-cookie" has the value "sid=abc123; Path=/; HttpOnly; SameSite=Lax"

  Scenario: A cookie is deleted with Max-Age=0
    When I send "GET" to "/logout"
    Then the status is 200
    And the header "set-cookie" has the value:
      """
      sid=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT
      """

  Scenario: A __Host- cookie is deleted with Secure, as browsers need
    When I send "GET" to "/logout-host"
    Then the header "set-cookie" has the value:
      """
      __Host-id=; Path=/; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure
      """

  Scenario: A value that std/cookie refuses is a 500
    When I send "GET" to "/bad-cookie"
    Then the status is 500
    And the body is "Internal Server Error"
    And the header "set-cookie" appears 0 times

  Scenario: header with Set-Cookie adds a header and keeps the cookies set before it
    When I send "GET" to "/raw-cookie"
    Then the header "set-cookie" appears 3 times
    And the header "set-cookie" has the value "a=1; Path=/; HttpOnly; SameSite=Lax"
    And the header "set-cookie" has the value "b=2; Path=/; HttpOnly; SameSite=Lax"
    And the header "set-cookie" has the value "raw=1"

  Scenario: try on a cookie that is not there is a 500, and an unwrap_or is the way
    When I send "GET" to "/require-sid"
    Then the status is 500
    And the body is "Internal Server Error"
    When I send "GET" to "/require-sid" with the cookie "sid=abc"
    Then the status is 200
    And the body is "sid=abc"

  Scenario Outline: A name or value that std/cookie refuses is a 500 and sets no cookie (<why>)
    When I send "GET" to "/set-cookie?name=<name>&value=<value>"
    Then the status is 500
    And the body is "Internal Server Error"
    And the header "set-cookie" appears 0 times

    Examples:
      | why                        | name       | value     |
      | a line break               | sid        | a%0D%0Ab  |
      | a semicolon                | sid        | a%3Bb     |
      | a comma                    | sid        | a%2Cb     |
      | a space                    | sid        | a%20b     |
      | a quote                    | sid        | %22q%22   |
      | non-ASCII                  | sid        | caf%C3%A9 |
      | a name that is not a token | bad%20name | x         |
      | a __Host- name             | __Host-id  | x         |

  Scenario: An empty value is a cookie
    When I send "GET" to "/set-cookie?name=sid&value="
    Then the status is 200
    And the header "set-cookie" has the value "sid=; Path=/; HttpOnly; SameSite=Lax"

  Scenario Outline: A cookie set by a filter stays on a 404 and is lost on a 500 (<path>)
    When I send "GET" to "<path>"
    Then the status is <status>
    And the header "set-cookie" appears <count> times

    Examples:
      | path        | status | count |
      | /track/ok   | 200    | 1     |
      | /track/none | 404    | 1     |
      | /track/fail | 500    | 0     |
