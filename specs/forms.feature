Feature: Form bodies
  `Bond.form(conn, name)`, `Bond.form_all` and `Bond.form_int` read a body of the type
  `application/x-www-form-urlencoded`, in the same way as the query string. The request must have exactly one
  `Content-Type`, and it must be that type (any case, any parameters). `POST /signup` and `POST /tags` of
  `specs/fixtures/app.agc` read a form.

  Background:
    Given the todo app

  Scenario: A form is decoded
    When I post to "/signup" as "application/x-www-form-urlencoded":
      """
      name=Ana+Mar%C3%ADa&age=30
      """
    Then the status is 201
    And the body is "welcome Ana María, 30"

  Scenario Outline: The content type may have a charset or another case (<type>)
    When I post to "/signup" as "<type>":
      """
      name=Ana&age=30
      """
    Then the status is 201

    Examples:
      | type                                             |
      | application/x-www-form-urlencoded; charset=utf-8 |
      | Application/X-WWW-Form-Urlencoded                |

  Scenario: A field may repeat and the order is kept
    When I post to "/tags" as "application/x-www-form-urlencoded":
      """
      tag=b&tag=a
      """
    Then the status is 200
    And the body is "tags=b,a"

  Scenario Outline: A body that is not marked as a form is a 400 (<type>)
    When I post to "/signup" as "<type>":
      """
      name=Ana&age=30
      """
    Then the status is 400
    And the body is "content type must be application/x-www-form-urlencoded"

    Examples:
      | type             |
      | text/plain       |
      | application/json |

  Scenario: A request with no content type is a 400
    When I send "POST" to "/signup" with the body "name=Ana&age=30"
    Then the status is 400
    And the body is "content type must be application/x-www-form-urlencoded"

  Scenario: More than one content type is a 400
    When I post to "/signup" as "application/x-www-form-urlencoded" and "text/plain":
      """
      name=Ana&age=30
      """
    Then the status is 400
    And the body is "content type must be application/x-www-form-urlencoded"

  Scenario Outline: A form that does not fit is a 400 that says why (<why>)
    When I post to "/signup" as "application/x-www-form-urlencoded":
      """
      <body>
      """
    Then the status is 400
    And the body is "<message>"

    Examples:
      | why          | body           | message                    |
      | empty        |                | form field name is missing |
      | no age       | name=Ana       | form field age is missing  |
      | not a number | name=Ana&age=x | age must be an integer     |
      | bad percent  | name=%zz&age=3 | the form is not valid      |
