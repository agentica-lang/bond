## Route patterns such as `/users/:id/posts/:post_id`.

import URI from "std/uri"

## The non-empty segments of a path, so `/a/` and `//a` are `/a`.
def segments(path: String) -> List[String] = path.split("/").select do |part| not part.empty? end

## The path with its non-empty segments only (`/a/`, `//a` and `/a//` are `/a`) and every escape decoded (`%73` is `s`,
## `%C3%A9` is `é`) except those of `/`, `\\`, `%`, `:` and the control characters, which stay, in capitals (`%2f` is
## `%2F`). One name has one spelling, the one that `Bond.static` reads.
def canonical(path: String) -> String = "/" + segments(unescape(path)).join("/")

## True when `pattern` starts with `/` and its `:name` segments have a name each, all different.
def valid?(pattern: String) -> Bool
  return false if not pattern.start_with?("/")

  names = segments(pattern).select do |part| part.start_with?(":") end
  names.all? do |name| name.length > 1 end and names.uniq.size == names.size
end

private

HEX = "0123456789ABCDEF"

# What stays escaped: the separators, the percent sign, a colon (a drive) and the control characters,
# which `Bond.static`
# refuses by name (`%252e` is a name with a percent sign, so the percent sign must not appear from a decoding).
KEPT = Set.new(["/", "\\", "%", ":"])

def unescape(path: String) -> String
  return path if not path.include?("%")

  pieces = path.split("%")
  text = pieces[0]
  run = ""
  for piece in pieces.drop(1)
    byte = hex_byte(piece)
    rest = after_digits(piece)
    if byte.some? and byte.unwrap! >= 128
      run = run + "%" + piece.slice(0, 2).upcase
      if not rest.empty?
        text = text + decode_run(run) + rest
        run = ""
      end
    else
      text = text + decode_run(run) + ascii_escape(piece, byte)
      run = ""
    end
  end

  text + decode_run(run)
end

def after_digits(piece: String) -> String
  return "" if piece.length <= 2

  piece.slice(2, piece.length - 2)
end

def hex_byte(piece: String) -> Optional[Int]
  return none if piece.length < 2

  high = HEX.index_of(piece.slice(0, 1).upcase)
  low = HEX.index_of(piece.slice(1, 1).upcase)
  return none if not high.some? or not low.some?

  some(high.unwrap! * 16 + low.unwrap!)
end

# `piece` is the text after a `%`: its two escape digits, then what follows. Not a byte of 128 or more.
def ascii_escape(piece: String, byte: Optional[Int]) -> String
  return "%#{piece}" if not byte.some?

  ch = String.from_code(byte.unwrap!)
  rest = after_digits(piece)
  return "%" + piece.slice(0, 2).upcase + rest if KEPT.include?(ch) or byte.unwrap! < 32 or byte.unwrap! == 127

  ch + rest
end

# Escapes of bytes of 128 or more: the characters they spell, or the escapes themselves when they are not UTF-8.
def decode_run(run: String) -> String
  return run if run.empty?

  decoded = URI.decode_uri_component(run)
  return run if not decoded.ok?

  decoded.unwrap!
end
