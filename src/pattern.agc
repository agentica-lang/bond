## Route patterns such as `/users/:id/posts/:post_id`.

## The non-empty segments of a path, so `/a/` and `//a` are `/a`.
export def segments(path: String) -> List[String]
  return path.split("/").select do |part| not part.empty? end
end

## True when `pattern` starts with `/` and its `:name` segments have a name each, all different.
export def valid?(pattern: String) -> Bool
  if not pattern.start_with?("/")
    return false
  end

  names = segments(pattern).select do |part| part.start_with?(":") end
  return names.all? do |name| name.length > 1 end and names.uniq.size == names.size
end
