## Route patterns such as `/users/:id/posts/:post_id`.

## The non-empty segments of a path, so `/a/` and `//a` are `/a`.
def segments(path: String) -> List[String] = path.split("/").select do |part| not part.empty? end

## The path with its non-empty segments only (`/a/`, `//a` and `/a//` are `/a`), the escapes of the characters that
## need none decoded (`%73` is `s`) and the others in capitals (`%c3` is `%C3`), so that one name has one spelling.
def canonical(path: String) -> String = "/" + segments(unescape_plain(path)).join("/")

## True when `pattern` starts with `/` and its `:name` segments have a name each, all different.
def valid?(pattern: String) -> Bool
  return false if not pattern.start_with?("/")

  names = segments(pattern).select do |part| part.start_with?(":") end
  names.all? do |name| name.length > 1 end and names.uniq.size == names.size
end

private

HEX = "0123456789ABCDEF"

PLAIN = Set.new("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".split(""))

def unescape_plain(path: String) -> String
  return path if not path.include?("%")

  pieces = path.split("%")
  pieces.drop(1).reduce(pieces[0]) do |text, piece| text + escape(piece) end
end

# `piece` is the text that follows a `%`.
def escape(piece: String) -> String
  return "%#{piece}" if piece.length < 2

  high = HEX.index_of(piece.slice(0, 1).upcase)
  low = HEX.index_of(piece.slice(1, 1).upcase)
  return "%#{piece}" if not high.some? or not low.some?

  plain = String.from_code(high.unwrap! * 16 + low.unwrap!)
  rest = piece.slice(2, piece.length - 2)
  return plain + rest if PLAIN.include?(plain)

  "%" + piece.slice(0, 2).upcase + rest
end
