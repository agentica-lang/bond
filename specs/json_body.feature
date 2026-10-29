Feature: JSON request bodies
  `Bond.json_body(conn, JSON.codec(NewUser))` decodes the body of the request into a struct. The request must say
  it is JSON (`application/json`, or a type that ends in `+json`, with any parameters), and the body must be one JSON
  document that fits the struct. Anything else is an error that makes a 400 with a short message, so a handler that
  uses `try` answers it without more code. `POST /users` of `specs/fixtures/app.agc` takes a `NewUser` with a name
  and an age.

  Background:
    Given the todo app

  Scenario: A JSON body is decoded into a struct
    When I send "POST" to "/users" with the header "content-type" set to "application/json" and the body:
      """
      {"name": "Ana", "age": 30}
      """
    Then the status is 201
    And the body is "hello Ana, 30"

  Scenario Outline: The content type may have a charset, another case or a +json type (<type>)
    When I send "POST" to "/users" with the header "content-type" set to "<type>" and the body:
      """
      {"name": "Ana", "age": 30}
      """
    Then the status is 201

    Examples:
      | type                            |
      | application/json; charset=utf-8 |
      | Application/JSON                |
      | application/vnd.api+json        |

  Scenario Outline: A body that is not marked as JSON is a 400 (<type>)
    When I send "POST" to "/users" with the header "content-type" set to "<type>" and the body:
      """
      {"name": "Ana", "age": 30}
      """
    Then the status is 400
    And the body is "content type must be application/json"

    Examples:
      | type              |
      | text/plain        |
      | application/jsonx |

  Scenario: A request with no content type is a 400
    When I send "POST" to "/users" with the body "{}"
    Then the status is 400
    And the body is "content type must be application/json"

  Scenario: An empty body is a 400
    When I send "POST" to "/users" with the header "content-type" set to "application/json"
    Then the status is 400
    And the body is "the body is empty"

  Scenario Outline: A body that does not fit the struct is a 400 that says why (<why>)
    When I send "POST" to "/users" with the header "content-type" set to "application/json" and the body:
      """
      <body>
      """
    Then the status is 400
    And the body starts with "invalid JSON: "
    And the body contains "<field>"

    Examples:
      | why        | body                             | field |
      | malformed  | {"name": "Ana", "age": 30        | JSON  |
      | no field   | {"name": "Ana"}                  | age   |
      | wrong type | {"name": "Ana", "age": "thirty"} | age   |
