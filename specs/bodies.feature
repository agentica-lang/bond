Feature: Request bodies
  `conn.body` is the body of the request as the client sent it, `Bytes` of any content. `Bond.body_text(conn)` reads it
  as text, as `HTTP.text` does: UTF-8 only, and a `charset` other than `utf-8` is refused. A body that does not decode
  is a 400 with a fixed message. `Bond.bytes(conn, status, body)` answers bytes as they are. The app of
  `specs/fixtures/app.agc` has `POST /body-text` (the text of the body) and `POST /body-echo` (the bytes, sent back).

  Background:
    Given the todo app

  Scenario: A text body is read as text
    When I post to "/body-text" as "text/plain; charset=utf-8":
      """
      café
      """
    Then the status is 200
    And the body is "text café"

  Scenario: A body with no charset is read as UTF-8
    When I send "POST" to "/body-text" with the body "ñandú"
    Then the status is 200
    And the body is "text ñandú"

  Scenario: A body that is not UTF-8 is a 400
    When I post the bytes "255 254 0" to "/body-text" as "text/plain"
    Then the status is 400
    And the body is "the body is not UTF-8 text"

  Scenario: Another charset is a 400
    When I post to "/body-text" as "text/plain; charset=iso-8859-1":
      """
      caf
      """
    Then the status is 400
    And the body is "the body is not UTF-8 text"

  Scenario: The bytes of a body come back as they were sent
    When I post the bytes "255 254 0 128 10" to "/body-echo" as "application/octet-stream"
    Then the status is 200
    And the header "content-type" is "application/octet-stream"
    And the body bytes are "255 254 0 128 10"

  Scenario: A JSON body that is not UTF-8 is a 400 with the same message
    When I post the bytes "123 34 255 34 125" to "/users" as "application/json"
    Then the status is 400
    And the body is "the body is not UTF-8 text"

  Scenario: A form body that is not UTF-8 is a 400 with the same message
    When I post the bytes "97 61 255" to "/signup" as "application/x-www-form-urlencoded"
    Then the status is 400
    And the body is "the body is not UTF-8 text"
