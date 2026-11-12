import Conns from "../src/conn"
import Files from "../src/files"

def request(headers: List[Header]) -> Conns.Conn
  Conns.from_request(
    HttpRequest(method: "GET", target: "/", path: "/", headers: headers, body: "".bytes, remote_addr: "127.0.0.1"),
  )
end

def rep() -> Files.Rep
  Files.Rep(
    type: "text/css; charset=utf-8",
    etag: "\"4-1\"",
    modified: 1,
    last_modified: "Thu, 01 Jan 1970 00:00:01 GMT",
    size: 4,
    cache_control: "public, max-age=60",
    encoding: "gzip",
    vary: true,
  )
end

def pairs(conn: Conns.Conn) -> List[String] = conn.response_headers.map do |field| "#{field.name}=#{field.value}" end

def main() -> Void
  Test.run([
    Test.test("a file answers with its headers in order") do
      answer = Files.respond(request([]), rep(), "x.css", some("body".bytes)).unwrap!
      Test.eq(
        pairs(answer).map do |line| line.split("=")[0] end,
        [
          "etag",
          "last-modified",
          "cache-control",
          "vary",
          "content-type",
          "x-content-type-options",
          "accept-ranges",
          "content-encoding",
        ],
      )
    end,
    Test.test("the headers of a file replace the same headers of the conn in any case, and keep the others") do
      before = Conns.add_header(Conns.add_header(request([]), "Cache-Control", "no-store"), "X-Keep", "k")
      answer = Files.respond(before, rep(), "x.css", some("body".bytes)).unwrap!
      cache_headers = answer.response_headers.filter do |field| field.name.downcase == "cache-control" end
      try Test.eq(cache_headers.size, 1)
      try Test.eq(answer.response_headers[0].name, "X-Keep")
      Test.assert(pairs(answer).include?("cache-control=public, max-age=60"), "the policy of the file")
    end,
    Test.test("a Set-Cookie of the conn stays after the headers of the file") do
      before = Conns.add_header(request([]), "Set-Cookie", "a=1")
      answer = Files.respond(before, rep(), "x.css", some("body".bytes)).unwrap!
      try Test.eq(pairs(answer)[0], "Set-Cookie=a=1")
      Test.eq(pairs(answer).size, 9)
    end,
    Test.test("a 304 has the validators and the policy, and no more") do
      matching = request([Header(name: "if-none-match", value: rep().etag)])
      answer = Files.respond(matching, rep(), "x.css", some("body".bytes)).unwrap!
      try Test.eq(answer.status, 304)
      Test.eq(
        pairs(answer),
        [
          "etag=\"4-1\"",
          "last-modified=Thu, 01 Jan 1970 00:00:01 GMT",
          "cache-control=public, max-age=60",
          "vary=Accept-Encoding",
        ],
      )
    end,
    Test.test("an attachment has its Content-Disposition before the encoding") do
      named = rep().with(attachment: some("a.css"))
      answer = Files.respond(request([]), named, "x.css", some("body".bytes)).unwrap!
      names = pairs(answer).map do |line| line.split("=")[0] end
      try Test.eq(names[7], "content-disposition")
      try Test.eq(names[8], "content-encoding")
      Test.assert(pairs(answer).include?("content-disposition=attachment; filename=\"a.css\""), "the name")
    end,
    Test.test("a range still has its Content-Range") do
      ranged = request([Header(name: "range", value: "bytes=1-2")])
      answer = Files.respond(ranged, rep(), "x.css", some("body".bytes)).unwrap!
      try Test.eq(answer.status, 206)
      Test.assert(pairs(answer).include?("content-range=bytes 1-2/4"), "content-range")
    end,
  ])
end
