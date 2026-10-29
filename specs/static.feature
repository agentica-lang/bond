Feature: Static files
  `Bond.static(app, "/assets", "fixtures/public")` serves the files of a folder under a path. It answers `GET` and
  `HEAD` with the file as a text body: `Content-Type` from `std/mime`, with `; charset=utf-8`,
  `X-Content-Type-Options: nosniff`, and the `Content-Length` that the server adds. A path that is not a file of the
  folder is a 404, and so is every way out of the folder or into a hidden name. A file over `max_bytes` (1 MiB at
  most) or a text file that is not UTF-8 is a 500, and a file whose type is not text is a 501, since a body is text.
  A route of the app wins over a file. The folder `specs/fixtures/public` has the files, and the app of
  `specs/fixtures/app.agc` serves it at `/assets` and, with `max_bytes` of 10, at `/small`. The links and the names
  that a checkout cannot hold are made for the scenario, in a folder that is removed after the request.

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

  Scenario: HEAD is answered like GET
    When I send "HEAD" to "/assets/hello.txt"
    Then the status is 200
    And the header "content-type" is "text/plain; charset=utf-8"

  Scenario Outline: Another method is a 405 under the prefix, for a missing file too (<path>)
    When I send "POST" to "<path>"
    Then the status is 405
    And the header "allow" is "GET, HEAD"

    Examples:
      | path                |
      | /assets/hello.txt   |
      | /assets/missing.txt |
      | /assets/sub         |

  Scenario Outline: A file that is not text by its type is a 501, before it is read (<path>)
    When I send "GET" to "<path>"
    Then the status is 501
    And the body is "Not Implemented"

    Examples:
      | path              |
      | /assets/pixel.png |
      | /assets/blob.bin  |
      | /assets/notes.xyz |

  Scenario Outline: A path that is not a file of the folder is a 404 (<why>)
    When I send "GET" to "<path>"
    Then the status is 404
    And the body is "not found"

    Examples:
      | why                      | path                       |
      | a missing file           | /assets/missing.txt        |
      | a folder                 | /assets/sub                |
      | a folder with a slash    | /assets/sub/               |
      | the prefix               | /assets                    |
      | a dot file               | /assets/.secret            |
      | dot dot                  | /assets/../app.agc         |
      | dot dot in the middle    | /assets/sub/../hello.txt   |
      | encoded dot dot          | /assets/%2e%2e/app.agc     |
      | an encoded slash         | /assets/..%2Fapp.agc       |
      | an absolute path         | /assets/%2Fetc%2Fpasswd    |
      | a backslash              | /assets/..%5Capp.agc       |
      | a NUL                    | /assets/hello.txt%00.png   |
      | a bad percent            | /assets/%zz                |
      | encoded twice            | /assets/%252e%252e/app.agc |
      | a name with an encoded % | /assets/%252esecret        |
      | a hidden folder          | /assets/.hid/inner.txt     |

  Scenario Outline: Links and special names in a folder made for the scenario (<path>)
    Given the app with a folder of links
    When I send "GET" to "<path>"
    Then the status is <status>

    Examples:
      | path                        | status |
      | /files/hello.txt            | 200    |
      | /files/alias.txt            | 200    |
      | /files/console.txt          | 200    |
      | /files/com0.txt             | 200    |
      | /files/to_env.txt           | 404    |
      | /files/to_hid.txt           | 404    |
      | /files/to_hid_dir/inner.txt | 404    |
      | /files/outside.txt          | 404    |
      | /files/out_dir/secret.txt   | 404    |
      | /files/con.txt              | 404    |
      | /files/CON.txt              | 404    |
      | /files/nul.css              | 404    |
      | /files/Aux.html             | 404    |
      | /files/com1.txt             | 404    |
      | /files/LPT9.txt             | 404    |

  Scenario: A route of the app wins over a file
    When I send "GET" to "/assets/override.txt"
    Then the status is 200
    And the body is "hello"

  Scenario Outline: A file over max_bytes or that is not UTF-8 text is a 500 (<path>)
    When I send "GET" to "<path>"
    Then the status is <status>

    Examples:
      | path              | status |
      | /small/tiny.txt   | 200    |
      | /small/ten.txt    | 200    |
      | /small/eleven.txt | 500    |
      | /small/hello.txt  | 500    |
      | /assets/bad.txt   | 500    |

  Scenario: A 500 for a file has the plain body
    When I send "GET" to "/assets/bad.txt"
    Then the body is "Internal Server Error"

  Scenario: A folder that does not exist stops the program when the app is built
    Given the Agentica program "fixtures/missing_root.agc"
    Then the program exits with code 1 within 5000 milliseconds

  Scenario: A file that is not text is said once on stderr, not on every request
    Given the Agentica program "fixtures/binary_twice.agc"
    Then the program exits with code 0 within 5000 milliseconds
    And stdout is:
      """
      501
      501

      """
    And stderr is:
      """
      bond: a static file is not text, and a binary file needs a body of bytes in std/http (Agentica #805, #803)

      """
