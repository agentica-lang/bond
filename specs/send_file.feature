Feature: Sending a file
  `Bond.send_file(conn, path)` answers with the file at `path`, with the `Content-Length` of its size and the type of `std/mime`. A name as the third argument makes it a download (`Content-Disposition:
  attachment`). `Range: bytes=a-b` gets a 206 with `Content-Range`, a range that starts beyond the end gets a 416, and
  the answer says `Accept-Ranges: bytes`. The answer has an `ETag` and a `Last-Modified`, and a `GET` or `HEAD` with a
  matching `If-None-Match` or a late enough `If-Modified-Since` is a 304 with no body. A file of at most `piece_bytes`
  (64 KiB by default) is read in one call, and a bigger one in pieces by a task; the bytes are the same.
  `Bond.static` answers through the same function. The routes of
  `specs/fixtures/app.agc` send `hello.txt` ("hello from a file", 17 bytes), and a file of 150 000 bytes (three pieces
  of 64 KiB) is written for the scenarios of the big file.

  Scenario: A file has its type, its length and the headers of a file
    Given the todo app
    When I send "GET" to "/download-plain"
    Then the status is 200
    And the body is "hello from a file"
    And the header "content-type" is "text/plain; charset=utf-8"
    And the header "content-length" is "17"
    And the header "accept-ranges" is "bytes"
    And the header "x-content-type-options" is "nosniff"
    And the header "content-disposition" is not set

  Scenario: The type comes from the file name, and a file that is not text is sent as it is
    Given the todo app
    When I send "GET" to "/download-png"
    Then the status is 200
    And the header "content-type" is "image/png"
    And the body bytes are "255 254 0 1"

  Scenario: An empty file is a 200 with no body
    Given the todo app
    When I send "GET" to "/download-empty"
    Then the status is 200
    And the header "content-length" is not set
    And the body bytes are ""

  Scenario: HEAD gets the headers with the length and no body
    Given the todo app
    When I send "HEAD" to "/download-plain"
    Then the status is 200
    And the header "content-length" is "17"
    And the header "accept-ranges" is "bytes"
    And the body bytes are ""

  Scenario: A name makes the file a download
    Given the todo app
    When I send "GET" to "/download"
    Then the status is 200
    And the header "content-disposition" is "attachment; filename=\"report.txt\""
    And the body is "hello from a file"

  Scenario: A name with characters outside ASCII has a plain fallback and the exact name
    Given the todo app
    When I send "GET" to "/download-unicode"
    Then the header "content-disposition" is "attachment; filename=\"caf_ _x_.txt\"; filename*=UTF-8''caf%C3%A9%20%22x%22.txt"

  Scenario: A name that tries to end the header has no control character, quote or backslash in the answer
    Given the todo app
    When I send "GET" to "/download-hostile"
    Then the status is 200
    And the header "content-disposition" is "attachment; filename=\"a__Set-Cookie: x=1__b_.txt\"; filename*=UTF-8''a%0D%0ASet-Cookie%3A%20x%3D1%00%22b%5C.txt"
    And the header "set-cookie" is not set
    And the body is "hello from a file"

  Scenario: An attachment with an empty name has no file name
    Given the todo app
    When I send "GET" to "/download-nameless"
    Then the header "content-disposition" is "attachment"

  Scenario: A custom status set after the file is kept, and the file is the body
    Given the todo app
    When I send "GET" to "/download-not-found"
    Then the status is 404
    And the body is "hello from a file"

  Scenario Outline: A file that is not a plain file of the disk is a 500 (<path>)
    Given the todo app
    When I send "GET" to "<path>"
    Then the status is 500
    And the body is "Internal Server Error"

    Examples:
      | path              |
      | /download-missing |
      | /download-folder  |

  Scenario Outline: A range of the file is a 206 with the bytes and the Content-Range (<range>)
    Given the todo app
    When I send "GET" to "/download-plain" with the header "range" set to "<range>"
    Then the status is 206
    And the body is "<body>"
    And the header "content-range" is "<content_range>"
    And the header "content-length" is "<length>"

    Examples:
      | range       | body              | content_range  | length |
      | bytes=0-4   | hello             | bytes 0-4/17   | 5      |
      | bytes=6-    | from a file       | bytes 6-16/17  | 11     |
      | bytes=-4    | file              | bytes 13-16/17 | 4      |
      | bytes=11-99 | a file            | bytes 11-16/17 | 6      |
      | bytes=16-16 | e                 | bytes 16-16/17 | 1      |
      | bytes=-99   | hello from a file | bytes 0-16/17  | 17     |

  Scenario Outline: A range that starts beyond the end is a 416 with the size (<range>)
    Given the todo app
    When I send "GET" to "/download-plain" with the header "range" set to "<range>"
    Then the status is 416
    And the header "content-range" is "bytes */17"
    And the body bytes are ""

    Examples:
      | range       |
      | bytes=17-   |
      | bytes=40-50 |
      | bytes=-0    |

  Scenario Outline: A range that is not one range of bytes is ignored and the whole file is sent (<range>)
    Given the todo app
    When I send "GET" to "/download-plain" with the header "range" set to "<range>"
    Then the status is 200
    And the body is "hello from a file"
    And the header "content-range" is not set

    Examples:
      | range           |
      | bytes=0-1,4-5   |
      | bytes=5-2       |
      | bytes=a-b       |
      | bytes=          |
      | items=0-3       |
      | bytes           |

  Scenario: A range with If-Range is ignored, since Bond has no validator to compare
    Given the todo app
    When I send "GET" to "/download-plain" with the range "bytes=0-4" and the validator "\"v1\""
    Then the status is 200
    And the body is "hello from a file"

  Scenario: HEAD with a range gets the 206 headers and no body
    Given the todo app
    When I send "HEAD" to "/download-plain" with the header "range" set to "bytes=0-4"
    Then the status is 206
    And the header "content-range" is "bytes 0-4/17"
    And the header "content-length" is "5"
    And the body bytes are ""

  Scenario: A file of several pieces is sent whole
    Given the app with a file of 150000 bytes
    When I send "GET" to "/big"
    Then the status is 200
    And the header "content-length" is "150000"
    And the body has 150000 bytes
    And the body bytes are the pattern from 0

  Scenario: A range that crosses the end of a piece
    Given the app with a file of 150000 bytes
    When I send "GET" to "/big" with the header "range" set to "bytes=65530-65545"
    Then the status is 206
    And the header "content-range" is "bytes 65530-65545/150000"
    And the body has 16 bytes
    And the body bytes are the pattern from 65530

  Scenario: A range far into a big file skips the bytes before it
    Given the app with a file of 150000 bytes
    When I send "GET" to "/big" with the header "range" set to "bytes=-100"
    Then the status is 206
    And the header "content-range" is "bytes 149900-149999/150000"
    And the body bytes are the pattern from 149900

  Scenario: A big file as a download
    Given the app with a file of 150000 bytes
    When I send "GET" to "/save"
    Then the status is 200
    And the header "content-disposition" is "attachment; filename=\"big file.bin\""
    And the header "content-type" is "application/octet-stream"
    And the body has 150000 bytes

  Scenario: Bond.static serves a range of a file too
    Given the app with a file of 150000 bytes
    When I send "GET" to "/files/big.bin" with the header "range" set to "bytes=149990-"
    Then the status is 206
    And the header "content-range" is "bytes 149990-149999/150000"
    And the body bytes are the pattern from 149990

  Scenario: A file has a validator, and a cache is told to ask each time
    Given the todo app
    When I send "GET" to "/download-plain"
    Then the status is 200
    And the header "etag" starts with "\""
    And the header "last-modified" ends with " GMT"
    And the header "cache-control" is "no-cache"

  Scenario Outline: The Cache-Control comes from max_age, or from the route when it set one (<path>)
    Given the todo app
    When I send "GET" to "<path>"
    Then the status is 200
    And the header "cache-control" is "<cache>"

    Examples:
      | path                | cache               |
      | /download-fresh     | no-cache            |
      | /download-kept      | private, max-age=600 |
      | /download-public    | public, max-age=600  |
      | /download-own-cache | max-age=5           |

  Scenario Outline: A max_age or a piece_bytes out of range is a 500 (<path>)
    Given the todo app
    When I send "GET" to "<path>"
    Then the status is 500

    Examples:
      | path                |
      | /download-age-low   |
      | /download-piece-low |

  Scenario Outline: A request that lists the validator, or a date that is not before the change, is a 304 (<headers>)
    Given the todo app
    When I send "GET" to "/download-plain"
    And I send "GET" to "/download-plain" with the headers:
      | <name> | <value> |
    Then the status is 304
    And the body bytes are ""
    And the header "etag" starts with "\""
    And the header "cache-control" is "no-cache"
    And the header "content-type" is not set

    Examples:
      | headers        | name              | value                                  |
      | the tag        | if-none-match     | {etag}                                 |
      | a weak tag     | if-none-match     | W/{etag}                               |
      | any tag        | if-none-match     | *                                      |
      | the date       | if-modified-since | {last_modified}                        |
      | a later date   | if-modified-since | Fri, 01 Jan 2100 00:00:00 GMT          |

  Scenario Outline: Another validator, an earlier date or a date that is not a date gets the file (<name> <value>)
    Given the todo app
    When I send "GET" to "/download-plain"
    And I send "GET" to "/download-plain" with the headers:
      | <name> | <value> |
    Then the status is 200
    And the body is "hello from a file"

    Examples:
      | name              | value                         |
      | if-none-match     | {other}                       |
      | if-modified-since | Thu, 01 Jan 1970 00:00:00 GMT |
      | if-modified-since | yesterday                     |
      | if-modified-since | Sunday, 06-Nov-94 08:49:37 GMT |

  Scenario: If-None-Match wins over If-Modified-Since
    Given the todo app
    When I send "GET" to "/download-plain"
    And I send "GET" to "/download-plain" with the headers:
      | if-none-match     | {other}         |
      | if-modified-since | {last_modified} |
    Then the status is 200

  Scenario: A HEAD request with a validator is a 304, and without one it has the validators and the length
    Given the todo app
    When I send "HEAD" to "/download-plain"
    Then the status is 200
    And the header "etag" starts with "\""
    And the header "last-modified" ends with " GMT"
    And the header "content-length" is "17"
    When I send "HEAD" to "/download-plain" with the headers:
      | if-none-match | {etag} |
    Then the status is 304

  Scenario: A validator that matches is a 304 even when the request has a Range
    Given the todo app
    When I send "GET" to "/download-plain"
    And I send "GET" to "/download-plain" with the headers:
      | if-none-match | {etag} |
      | range         | bytes=0-4 |
    Then the status is 304
    And the header "content-range" is not set

  Scenario Outline: A file of several pieces and one read in one call have the same bytes (<path>)
    Given the app with a file of 150000 bytes
    When I send "GET" to "<path>"
    Then the status is 200
    And the header "content-length" is "150000"
    And the body has 150000 bytes
    And the body bytes are the pattern from 0

    Examples:
      | path                 |
      | /big                 |
      | /pieces              |
      | /whole               |
      | /files/big.bin       |
      | /pieces-files/big.bin |
      | /whole-files/big.bin |

  Scenario Outline: A range across the edge of a piece, as the piece size sets it (<path>)
    Given the app with a file of 150000 bytes
    When I send "GET" to "<path>" with the header "range" set to "bytes=4090-4105"
    Then the status is 206
    And the header "content-range" is "bytes 4090-4105/150000"
    And the body has 16 bytes
    And the body bytes are the pattern from 4090

    Examples:
      | path                  |
      | /pieces               |
      | /whole                |
      | /pieces-files/big.bin |
      | /whole-files/big.bin  |

  Scenario Outline: A range at the end of the file, as the piece size sets it (<path>)
    Given the app with a file of 150000 bytes
    When I send "GET" to "<path>" with the header "range" set to "bytes=-100"
    Then the status is 206
    And the header "content-range" is "bytes 149900-149999/150000"
    And the body bytes are the pattern from 149900

    Examples:
      | path                  |
      | /pieces               |
      | /whole                |
      | /pieces-files/big.bin |
      | /whole-files/big.bin  |

  Scenario: A piece_bytes out of range for a file is a 500
    Given the app with a file of 150000 bytes
    When I send "GET" to "/bad-piece"
    Then the status is 500

  Scenario: The file changes between requests, and the validators follow it
    Given the app with a cache of 0 bytes over a folder that I edit
    And the file "a.txt" holds "one" as of the time 1700000000
    When I send "GET" to "/sent"
    Then the status is 200
    And the header "last-modified" is "Tue, 14 Nov 2023 22:13:20 GMT"
    And the body is "one"
    When the file "a.txt" holds "three" as of the time 1700000001
    When I send "GET" to "/sent" with the headers:
      | if-modified-since | Tue, 14 Nov 2023 22:13:20 GMT |
    Then the status is 200
    And the header "last-modified" is "Tue, 14 Nov 2023 22:13:21 GMT"
    And the body is "three"
