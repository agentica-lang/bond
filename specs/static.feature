Feature: Static files
  `Bond.static(app, "/assets", "fixtures/public")` serves the files of a folder under a path. It answers `GET` and
  `HEAD` with the file as a text body: `Content-Type` from `std/mime`, with `; charset=utf-8` for text types,
  `X-Content-Type-Options: nosniff`, and the `Content-Length` that the server adds. A path that is not a file of the
  folder is a 404, and so is every way out of the folder. A file over `max_bytes` (1 MiB at most) or that is not UTF-8
  text is a 500, since a body is text. A route of the app wins over a file. The folder `specs/fixtures/public` has the
  files, and the app of `specs/fixtures/app.agc` serves it at `/assets` and, with `max_bytes` of 10, at `/small`.

  Background:
    Given the todo app

  Scenario: A text file is served with its type and the headers of a static file
    When I send "GET" to "/assets/hello.txt"
    Then the status is 200
    And the body is "hello from a file"
    And the header "content-type" is "text/plain; charset=utf-8"
    And the header "x-content-type-options" is "nosniff"

  Scenario Outline: The type comes from the extension, with a charset for text (<path>)
    When I send "GET" to "<path>"
    Then the status is 200
    And the header "content-type" is "<type>"

    Examples:
      | path                  | type                            |
      | /assets/style.css     | text/css; charset=utf-8         |
      | /assets/data.json     | application/json; charset=utf-8 |
      | /assets/sub/page.html | text/html; charset=utf-8        |
      | /assets/logo.svg      | image/svg+xml; charset=utf-8    |
      | /assets/notes.xyz     | application/octet-stream        |

  Scenario: HEAD is answered like GET
    When I send "HEAD" to "/assets/hello.txt"
    Then the status is 200
    And the header "content-type" is "text/plain; charset=utf-8"

  Scenario: Another method is a 405
    When I send "POST" to "/assets/hello.txt"
    Then the status is 405
    And the header "allow" is "GET, HEAD"

  Scenario Outline: A path that is not a file of the folder is a 404 (<why>)
    When I send "GET" to "<path>"
    Then the status is 404
    And the body is "not found"

    Examples:
      | why                      | path                     |
      | a missing file           | /assets/missing.txt      |
      | a folder                 | /assets/sub              |
      | a folder with a slash    | /assets/sub/             |
      | the prefix               | /assets                  |
      | a dot file               | /assets/.secret          |
      | dot dot                  | /assets/../app.agc       |
      | dot dot in the middle    | /assets/sub/../hello.txt |
      | encoded dot dot          | /assets/%2e%2e/app.agc   |
      | an encoded slash         | /assets/..%2Fapp.agc     |
      | an absolute path         | /assets/%2Fetc%2Fpasswd  |
      | a backslash              | /assets/..%5Capp.agc     |
      | a NUL                    | /assets/hello.txt%00.png |
      | a bad percent            | /assets/%zz              |
      | a link out of the folder | /assets/outside.txt      |

  Scenario: A link inside the folder is followed
    When I send "GET" to "/assets/alias.txt"
    Then the status is 200
    And the body is "hello from a file"

  Scenario: A route of the app wins over a file
    When I send "GET" to "/assets/override.txt"
    Then the status is 200
    And the body is "hello"

  Scenario Outline: A file over max_bytes or that is not UTF-8 text is a 500 (<path>)
    When I send "GET" to "<path>"
    Then the status is <status>

    Examples:
      | path             | status |
      | /small/tiny.txt  | 200    |
      | /small/hello.txt | 500    |
      | /assets/blob.bin | 500    |

  Scenario: A 500 for a file has the plain body
    When I send "GET" to "/assets/blob.bin"
    Then the body is "Internal Server Error"
