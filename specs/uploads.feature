Feature: Uploads
  `Bond.uploads` reads a `multipart/form-data` body as it arrives: the text fields go to `Bond.form` and the files to
  a private folder, under names of Bond's own, removed after the answer. The body is read after the before filters,
  for a request that found its route. The program of `specs/fixtures/upload_server.agc` listens on 127.0.0.1 and a
  free port, with a file of at most 1 KiB, a text field of at most 256 bytes and `Bond.csrf`.

  Scenario: Two fields and a file over a real socket, and the file is removed after the answer
    Given the upload server listens on a free port
    When I post the fields "title=trip&tag=beach" and the file "notes.txt" holding "hello file" to "/upload" over the socket
    Then the status is 200
    And the body has the line "title=trip"
    And the body has the line "tag=beach"
    And the body has the line "file photo notes.txt text/plain 10 hello file"
    And the header "x-upload-folders" is "1"
    And the saved file of the answer is removed

  Scenario: A file over the limit is a 413 that closes the connection, and the server goes on
    Given the upload server listens on a free port
    When I post the fields "title=big" and a file of 2000 bytes to "/upload" over the socket
    Then the status is 413
    And the header "connection" is "close"
    When I get "/hello" over the socket
    Then the body is "hello"

  Scenario: A chunked upload with a bad chunk is a 400 that closes the connection, and the server goes on
    Given the upload server listens on a free port
    When I post the multipart chunks "zz~aaaaa~0~~" to "/upload" over a raw socket
    Then the status is 400
    And the header "connection" is "close"
    When I get "/hello" over the socket
    Then the body is "hello"

  Scenario: A text field over the limit is a 413 that closes the connection
    Given the upload server listens on a free port
    When I post a text field of 300 bytes and a file to "/upload" over the socket
    Then the status is 413
    And the header "connection" is "close"

  Scenario: A request that a before filter refuses is not read, so no folder is made
    Given the upload server listens on a free port
    When I post the file "notes.txt" holding "hello file" to "/upload" over the socket from another site
    Then the status is 403
    And the header "x-upload-folders" is "0"

  Scenario: A request to a path with no route is not read, so no folder is made
    Given the upload server listens on a free port
    When I post the fields "title=x" and the file "notes.txt" holding "hello file" to "/nothing" over the socket
    Then the status is 404
    And the header "x-upload-folders" is "0"

  Scenario: A filename with a path is shown by its last part and never used as a path
    Given the upload server listens on a free port
    When I post the fields "title=x" and the file "../../etc/passwd" holding "not a password" to "/upload" over the socket
    Then the status is 200
    And the body has the line "file photo passwd text/plain 14 not a password"
    And the saved path of the answer does not have "etc"
    And the saved path of the answer does not have ".."
