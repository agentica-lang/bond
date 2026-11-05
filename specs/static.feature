Feature: Static files
  `Bond.static(app, "/assets", "fixtures/public")` serves the files of a folder under a path. It answers `GET` and
  `HEAD` with the bytes of the file, with an `ETag` and a `Last-Modified` (a 304 for a request that has them): `Content-Type` from `std/mime`, with `; charset=utf-8` for a text type,
  `X-Content-Type-Options: nosniff`, and the `Content-Length` that the server adds. A path that is not a file of the
  folder is a 404, and so is every way out of the folder or into a hidden name. A file over `max_bytes` (1 GiB by
  default) is a 500. A route of the app wins over a file. The folder `specs/fixtures/public` has the files, and the app of
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

  Scenario Outline: A file that is not text is served as the bytes it holds (<path>)
    When I send "GET" to "<path>"
    Then the status is 200
    And the header "content-type" is "<type>"
    And the body bytes are "<bytes>"

    Examples:
      | path              | type                     | bytes       |
      | /assets/pixel.png | image/png                | 255 254 0 1 |
      | /assets/blob.bin  | application/octet-stream | 255 254 0 1 |
      | /assets/notes.xyz | application/octet-stream | 120 121 122 |

  Scenario: An empty file is a 200 with no bytes
    When I send "GET" to "/assets/empty.txt"
    Then the status is 200
    And the body bytes are ""

  Scenario: A text file is not checked to be UTF-8
    When I send "GET" to "/assets/bad.txt"
    Then the status is 200
    And the header "content-type" is "text/plain; charset=utf-8"
    And the body bytes are "255 254 0 1"

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

  Scenario Outline: A file over max_bytes is a 500 (<path>)
    When I send "GET" to "<path>"
    Then the status is <status>

    Examples:
      | path              | status |
      | /small/tiny.txt   | 200    |
      | /small/ten.txt    | 200    |
      | /small/eleven.txt | 500    |
      | /small/hello.txt  | 500    |

  Scenario: A 500 for a file has the plain body
    When I send "GET" to "/small/eleven.txt"
    Then the body is "Internal Server Error"

  Scenario: A folder that does not exist stops the program when the app is built
    Given the Agentica program "fixtures/missing_root.agc"
    Then the program exits with code 1 within 5000 milliseconds

  Scenario: A folder with a negative max_age stops the program when the app is built
    Given the Agentica program "fixtures/bad_max_age.agc"
    Then the program exits with code 1 within 5000 milliseconds

  Scenario: A file has a validator and is asked about each time
    When I send "GET" to "/assets/hello.txt"
    Then the status is 200
    And the header "etag" starts with "\""
    And the header "etag" ends with "\""
    And the header "cache-control" is "no-cache"

  Scenario Outline: A request that lists the validator is a 304 with no body (<value>)
    When I send "GET" to "/assets/hello.txt"
    And I send "GET" to "/assets/hello.txt" with If-None-Match "<value>"
    Then the status is 304
    And the body is ""
    And the header "cache-control" is "no-cache"
    And the header "etag" starts with "\""

    Examples:
      | value                |
      | {etag}               |
      | W/{etag}             |
      | *                    |
      | {other}, {etag}      |
      | {etag},{other}       |

  Scenario: A HEAD request is a 304 too
    When I send "GET" to "/assets/hello.txt"
    And I send "HEAD" to "/assets/hello.txt" with If-None-Match "{etag}"
    Then the status is 304

  Scenario: Another validator gets the file
    When I send "GET" to "/assets/hello.txt"
    And I send "GET" to "/assets/hello.txt" with If-None-Match "{other}"
    Then the status is 200
    And the body is "hello from a file"

  Scenario: The validator of one file does not answer for another
    When I send "GET" to "/assets/hello.txt"
    And I send "GET" to "/assets/style.css" with If-None-Match "{etag}"
    Then the status is 200

  Scenario Outline: A fingerprint is trusted only when the folder says so (<path>)
    When I send "GET" to "<path>"
    Then the status is 200
    And the header "cache-control" is "<cache>"

    Examples:
      | path                               | cache                               |
      | /assets/app.3f9a1c2b.js            | no-cache                            |
      | /versioned/app.3f9a1c2b.js         | public, max-age=31536000, immutable |
      | /versioned/main-0123abcd.chunk.css | public, max-age=31536000, immutable |
      | /versioned/short.abc123.txt        | no-cache                            |
      | /versioned/hello.txt               | no-cache                            |
      | /cached/hello.txt                  | public, max-age=3600                |
      | /cached/app.3f9a1c2b.js            | public, max-age=3600                |

  Scenario Outline: A date or a time in a name is not a fingerprint, even where fingerprints are trusted (<path>)
    When I send "GET" to "<path>"
    Then the status is 200
    And the header "cache-control" is "<cache>"

    Examples:
      | path                              | cache                |
      | /assets/report.20240131.pdf       | no-cache             |
      | /assets/photo-1712345678.png      | no-cache             |
      | /versioned/report.20240131.pdf    | no-cache             |
      | /versioned/photo-1712345678.png   | no-cache             |
      | /cached/report.20240131.pdf       | public, max-age=3600 |

  Scenario: The answer to a Range request has the validator
    When I send "GET" to "/assets/hello.txt" with the header "range" set to "bytes=0-4"
    Then the status is 206
    And the header "etag" starts with "\""


  Scenario: A file has the time of its last change
    When I send "GET" to "/assets/hello.txt"
    Then the header "last-modified" ends with " GMT"

  Scenario Outline: A request with a date that is not before the change is a 304, and one with an earlier date is not (<date>)
    When I send "GET" to "/assets/hello.txt"
    And I send "GET" to "/assets/hello.txt" with the headers:
      | if-modified-since | <date> |
    Then the status is <status>

    Examples:
      | date                          | status |
      | Fri, 01 Jan 2100 00:00:00 GMT | 304    |
      | Thu, 01 Jan 1970 00:00:00 GMT | 200    |

  Scenario: If-None-Match wins over If-Modified-Since
    When I send "GET" to "/assets/hello.txt"
    And I send "GET" to "/assets/hello.txt" with the headers:
      | if-none-match     | {other}                       |
      | if-modified-since | Fri, 01 Jan 2100 00:00:00 GMT |
    Then the status is 200

  Scenario Outline: A .gz file that is not older than the file is sent to a client that takes gzip (cache <cache>, gzip at <time>)
    Given the app with a cache of <cache> bytes over a folder that I edit
    And the file "a.css" holds "body { color: red }" as of the time 1700000000
    And the file "a.css.gz" holds the gzip of "body { color: red }" as of the time <time>
    When I send "GET" to "/files/a.css" with the headers:
      | accept-encoding | br, gzip;q=0.8 |
    Then the status is 200
    And the header "content-encoding" is "gzip"
    And the header "vary" is "Accept-Encoding"
    And the header "content-type" is "text/css; charset=utf-8"
    And the header "etag" ends with "-gz\""
    And the body gunzipped is "body { color: red }"

    Examples:
      | cache  | time       |
      | 0      | 1700000000 |
      | 0      | 1700000001 |
      | 100000 | 1700000000 |
      | 100000 | 1700000001 |

  Scenario Outline: A .gz file older than the file is not sent (cache <cache>)
    Given the app with a cache of <cache> bytes over a folder that I edit
    And the file "a.css" holds "body { color: red }" as of the time 1700000000
    And the file "a.css.gz" holds the gzip of "body { color: blue }" as of the time 1699999999
    When I send "GET" to "/files/a.css" with the headers:
      | accept-encoding | gzip |
    Then the status is 200
    And the header "content-encoding" is not set
    And the header "vary" is "Accept-Encoding"
    And the body is "body { color: red }"

    Examples:
      | cache  |
      | 0      |
      | 100000 |

  Scenario Outline: The file as it is, for a client that does not take gzip or asks for a part (<headers>, cache <cache>)
    Given the app with a cache of <cache> bytes over a folder that I edit
    And the file "a.css" holds "body { color: red }" as of the time 1700000000
    And the file "a.css.gz" holds the gzip of "body { color: red }" as of the time 1700000000
    When I send "GET" to "/files/a.css" with the headers:
      | <name> | <value> |
    Then the status is <status>
    And the header "content-encoding" is not set
    And the header "vary" is "Accept-Encoding"
    And the body is "<body>"

    Examples:
      | headers          | cache  | name            | value        | status | body                |
      | no encoding      | 0      | x-other         | 1            | 200    | body { color: red } |
      | gzip refused     | 0      | accept-encoding | gzip;q=0, br | 200    | body { color: red } |
      | another encoding | 100000 | accept-encoding | deflate, br  | 200    | body { color: red } |
      | a range          | 0      | range           | bytes=0-3    | 206    | body                |
      | a range          | 100000 | range           | bytes=0-3    | 206    | body                |

  Scenario: A range of a file that takes gzip is a part of the file, not of the compressed bytes
    Given the app with a cache of 100000 bytes over a folder that I edit
    And the file "a.css" holds "body { color: red }" as of the time 1700000000
    And the file "a.css.gz" holds the gzip of "body { color: red }" as of the time 1700000000
    When I send "GET" to "/files/a.css" with the headers:
      | accept-encoding | gzip      |
      | range           | bytes=0-3 |
    Then the status is 206
    And the header "content-encoding" is not set
    And the body is "body"

  Scenario: The tag of the compressed file is not the one of the file, and it is a 304 for the same client
    Given the app with a cache of 100000 bytes over a folder that I edit
    And the file "a.css" holds "body { color: red }" as of the time 1700000000
    And the file "a.css.gz" holds the gzip of "body { color: red }" as of the time 1700000000
    When I send "GET" to "/files/a.css" with the headers:
      | accept-encoding | gzip |
    And I send "GET" to "/files/a.css" with the headers:
      | accept-encoding | gzip   |
      | if-none-match   | {etag} |
    Then the status is 304
    And the header "vary" is "Accept-Encoding"
    When I send "GET" to "/files/a.css" with the headers:
      | accept-encoding | identity |
      | if-none-match   | {etag}   |
    Then the status is 200
    And the body is "body { color: red }"

  Scenario Outline: A file that is not text is never sent compressed, whatever is next to it (<name>, cache <cache>)
    Given the app with a cache of <cache> bytes over a folder that I edit
    And the file "<name>" holds "abc" as of the time 1700000000
    And the file "<name>.gz" holds the gzip of "abc" as of the time 1700000000
    When I send "GET" to "/files/<name>" with the headers:
      | accept-encoding | gzip |
    Then the status is 200
    And the header "content-encoding" is not set
    And the body is "abc"

    Examples:
      | name  | cache  |
      | a.png | 0      |
      | a.png | 100000 |

  Scenario Outline: A .gz file that is a link to a file outside the folder is not sent (cache <cache>)
    Given the app with a cache of <cache> bytes over a folder that I edit
    And the file "a.css" holds "body { color: red }" as of the time 1700000000
    And the outside file holds "secret"
    And the file "a.css.gz" is a link to the outside file
    When I send "GET" to "/files/a.css" with the headers:
      | accept-encoding | gzip |
    Then the status is 200
    And the header "content-encoding" is not set
    And the body is "body { color: red }"

    Examples:
      | cache  |
      | 0      |
      | 100000 |

  Scenario Outline: A text file with no .gz file has no compression to offer (cache <cache>)
    Given the app with a cache of <cache> bytes over a folder that I edit
    And the file "a.css" holds "body { color: red }" as of the time 1700000000
    When I send "GET" to "/files/a.css" with the headers:
      | accept-encoding | gzip |
    Then the status is 200
    And the header "content-encoding" is not set
    And the header "vary" is "Accept-Encoding"

    Examples:
      | cache  |
      | 0      |
      | 100000 |

  Scenario: Spellings of a name add nothing to the cache, so they cannot push out the entries of other files
    Given the app with a cache of 2000 bytes over a folder that I edit
    And the file "a.txt" holds "aaa" as of the time 1700000000
    And the file "b.txt" holds "bbb" as of the time 1700000000
    When I send "GET" to "/files/b.txt"
    And I send "GET" to "/files/%61.txt"
    And I send "GET" to "/files/a%2Etxt"
    And I send "GET" to "/files/%61%2Etxt"
    And I send "GET" to "/files/a.tx%74"
    Then the body is "aaa"
    When the file "b.txt" holds "BBB" as of the time 1700000000
    And I send "GET" to "/files/b.txt"
    Then the body is "bbb"

  Scenario: A folder with no cache reads the file each time
    Given the app with a cache of 0 bytes over a folder that I edit
    And the file "a.txt" holds "one" as of the time 1700000000
    When I send "GET" to "/files/a.txt"
    Then the body is "one"
    When the file "a.txt" holds "two" as of the time 1700000000
    And I send "GET" to "/files/a.txt"
    Then the body is "two"

  Scenario: A file in the cache is read again when its size or its time of change is not the same
    Given the app with a cache of 100000 bytes over a folder that I edit
    And the file "a.txt" holds "one" as of the time 1700000000
    When I send "GET" to "/files/a.txt"
    Then the header "last-modified" is "Tue, 14 Nov 2023 22:13:20 GMT"
    And the body is "one"
    When the file "a.txt" holds "two" as of the time 1700000001
    And I send "GET" to "/files/a.txt"
    Then the header "last-modified" is "Tue, 14 Nov 2023 22:13:21 GMT"
    And the body is "two"
    When the file "a.txt" holds "three" as of the time 1700000001
    And I send "GET" to "/files/a.txt"
    Then the body is "three"

  Scenario: A hit does not read the file again while its size and time are the same
    Given the app with a cache of 100000 bytes over a folder that I edit
    And the file "a.txt" holds "one" as of the time 1700000000
    When I send "GET" to "/files/a.txt"
    Then the body is "one"
    When the file "a.txt" holds "two" as of the time 1700000000
    And I send "GET" to "/files/a.txt"
    Then the body is "one"

  Scenario: A file that is gone is a 404 and not the bytes that were kept
    Given the app with a cache of 100000 bytes over a folder that I edit
    And the file "a.txt" holds "one" as of the time 1700000000
    When I send "GET" to "/files/a.txt"
    Then the status is 200
    When the file "a.txt" is removed
    And I send "GET" to "/files/a.txt"
    Then the status is 404

  Scenario: A fingerprinted file of a folder that trusts fingerprints is not checked against the disk
    Given the app with a cache of 100000 bytes over a folder that I edit
    And the file "app.3f9a1c2b.css" holds "body {}" as of the time 1700000000
    When I send "GET" to "/versioned/app.3f9a1c2b.css"
    Then the header "cache-control" is "public, max-age=31536000, immutable"
    And the body is "body {}"
    When the file "app.3f9a1c2b.css" is removed
    And I send "GET" to "/versioned/app.3f9a1c2b.css"
    Then the status is 200
    When I send "GET" to "/files/app.3f9a1c2b.css"
    Then the status is 404

  Scenario: A cache that is full is emptied, so it holds no more than its size
    Given the app with a cache of 2000 bytes over a folder that I edit
    And the file "a.txt" holds "aaa" as of the time 1700000000
    And the file "b.txt" holds "bbb" as of the time 1700000000
    And the file "c.txt" holds "ccc" as of the time 1700000000
    And the file "d.txt" holds "ddd" as of the time 1700000000
    When I send "GET" to "/files/a.txt"
    And I send "GET" to "/files/b.txt"
    And I send "GET" to "/files/c.txt"
    And the file "a.txt" holds "AAA" as of the time 1700000000
    And the file "b.txt" holds "BBB" as of the time 1700000000
    And I send "GET" to "/files/b.txt"
    Then the body is "bbb"
    When I send "GET" to "/files/d.txt"
    And I send "GET" to "/files/a.txt"
    Then the body is "AAA"

  Scenario: A piece_bytes below the minimum stops the program when the app is built
    Given the Agentica program "fixtures/bad_piece_bytes.agc"
    Then the program exits with code 1 within 5000 milliseconds
