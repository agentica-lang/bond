Feature: Query strings
  `Bond.query(conn, name)` is the first value of a name in the query string, decoded with `std/uri`: `+` is a space
  and `%XX` is a byte. `Bond.query_all` is every value of a name, in order, and `Bond.query_int` is a whole number.
  A name that is missing, a number that is not one and a bad `%` are errors that make a 400, so `try` answers them.
  `conn.query` is still the raw text. `GET /search` and `GET /items` of `specs/fixtures/app.agc` read it.

  Background:
    Given the todo app

  Scenario: A value is decoded
    When I send "GET" to "/search?q=caf%C3%A9+au+lait"
    Then the status is 200
    And the body is "q=café au lait page=1 tags="

  Scenario: A name may repeat and the order is kept, and a number is read
    When I send "GET" to "/search?q=x&tag=b&page=3&tag=a"
    Then the status is 200
    And the body is "q=x page=3 tags=b,a"

  Scenario: A piece with no equal sign has an empty value
    When I send "GET" to "/search?q&tag"
    Then the status is 200
    And the body is "q= page=1 tags="

  Scenario Outline: A query that does not fit is a 400 that says why (<why>)
    When I send "GET" to "<target>"
    Then the status is 400
    And the body is "<message>"

    Examples:
      | why          | target         | message                       |
      | no name      | /search?page=2 | query parameter q is missing  |
      | bad percent  | /search?q=%zz  | the query string is not valid |
      | bad UTF-8    | /search?q=%FF  | the query string is not valid |
      | not a number | /items?n=many  | n must be an integer          |
      | no number    | /items         | query parameter n is missing  |

  Scenario Outline: A number is read from the query string (<target>)
    When I send "GET" to "<target>"
    Then the status is <status>
    And the body is "<body>"

    Examples:
      | target                        | status | body                 |
      | /items?n=5                    | 200    | 5 items              |
      | /items?n=-3                   | 200    | -3 items             |
      | /items?n=%2B5                 | 200    | 5 items              |
      | /items?n=+5                   | 400    | n must be an integer |
      | /items?n=99999999999999999999 | 400    | n must be an integer |

  Scenario: An empty value is a value
    When I send "GET" to "/search?q="
    Then the status is 200
    And the body is "q= page=1 tags="

  Scenario Outline: A bad percent anywhere makes the whole query string invalid (<where>)
    When I send "GET" to "<target>"
    Then the status is 400
    And the body is "the query string is not valid"

    Examples:
      | where            | target             |
      | in another value | /search?q=hi&x=%zz |
      | in a name        | /search?q=hi&%zz=1 |

  Scenario Outline: All the fields are read at once with query_params (<target>)
    When I send "GET" to "<target>"
    Then the status is <status>
    And the body is "<body>"

    Examples:
      | target                | status | body                          |
      | /params?a=1&b=x+y&a=2 | 200    | a=1\|2;b=x y                  |
      | /params               | 200    |                               |
      | /params?a=1&b=%zz     | 400    | the query string is not valid |
