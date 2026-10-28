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

## Gives the params of `path` when it matches `pattern`: each `:name` segment takes the text of the segment of
## `path` at its place, and every other segment must be equal.
export def matches(pattern: String, path: String) -> Result[Map[String, String]]
  wanted = segments(pattern)
  found = segments(path)
  if wanted.size != found.size
    return error("no match")
  end

  params: Map[String, String] = {}
  for i in 0...wanted.size
    if wanted[i].start_with?(":")
      params = params.put(wanted[i].slice(1, wanted[i].length - 1), found[i])
    elsif wanted[i] != found[i]
      return error("no match")
    end
  end

  return ok(params)
end
