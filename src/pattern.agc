## Route patterns such as `/users/:id/posts/:post_id`.

## The non-empty segments of a path, so `/a/` and `//a` are `/a`.
def segments(path: String) -> List[String] = path.split("/").select do |part| not part.empty? end

## True when `pattern` starts with `/` and its `:name` segments have a name each, all different.
def valid?(pattern: String) -> Bool
  return false if not pattern.start_with?("/")

  names = segments(pattern).select do |part| part.start_with?(":") end
  names.all? do |name| name.length > 1 end and names.uniq.size == names.size
end
