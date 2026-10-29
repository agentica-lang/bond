## The routes as a tree of path segments, as in the compiled router of Falcon. A node holds the routes that end at it
## (a handler for each method), its literal children by name, and at most one param child. A request walks the tree
## once, so the work depends on the length of the path and not on the number of routes.

import Pattern from "pattern"
import {Handler} from "conn"

## A step of the tree. `name` is the param name of a param child (the node itself has none: it is the child's).
export struct Node
  literals: Map[String, Node]
  params: List[Node]
  name: String
  handlers: Map[String, Handler]
end

## The node that a route found, with the params on the way to it.
export struct Found
  node: Node
  params: Map[String, String]
end

# The route being added, so that its parts travel together down the tree.
struct Route
  method: String
  pattern: String
  handler: Handler
end

## A tree with no route.
export def empty() -> Node
  return Node(literals: {}, params: [], name: "", handlers: {})
end

## Adds the route to the tree. It is an `error` when the same method and pattern are already there (a trailing or a
## double slash does not make another pattern), or when the pattern has another param name than the routes already in
## the tree at the same place: `/users/:id` and `/users/:name/posts` cannot both be.
export def add(root: Node, method: String, pattern: String, handler: Handler) -> Result[Node]
  return insert(root, Pattern.segments(pattern), Route(method: method, pattern: pattern, handler: handler))
end

## The node that holds the route of `path`, with the params. A literal segment is tried before the param of the same
## place, and when the literal branch has no route to the end the walk goes back to the param. `error` when no route
## has this path (the method is not looked at here).
export def find(root: Node, path: String) -> Result[Found]
  return walk(root, Pattern.segments(path), 0, {})
end

def insert(node: Node, parts: List[String], route: Route) -> Result[Node]
  if parts.empty?
    if node.handlers.key?(route.method)
      return error("bond: the route #{route.method} #{route.pattern} is added twice")
    end

    return ok(node.with(handlers: node.handlers.put(route.method, route.handler)))
  end

  part = parts[0]
  rest = parts.drop(1)
  if part.start_with?(":")
    return insert_param(node, part.slice(1, part.length - 1), rest, route)
  end

  child = node.literals.get(part, empty())
  updated = try insert(child, rest, route)
  return ok(node.with(literals: node.literals.put(part, updated)))
end

def insert_param(node: Node, name: String, rest: List[String], route: Route) -> Result[Node]
  child = empty().with(name: name)
  if not node.params.empty?
    child = node.params[0]
  end

  if child.name != name
    return error("bond: the route #{route.method} #{route.pattern} names the param #{name}, not #{child.name}")
  end

  updated = try insert(child, rest, route)
  return ok(node.with(params: [updated]))
end

def walk(node: Node, parts: List[String], at: Int, params: Map[String, String]) -> Result[Found]
  if at == parts.size
    if node.handlers.empty?
      return error("no route")
    end

    return ok(Found(node: node, params: params))
  end

  part = parts[at]
  if node.literals.key?(part)
    found = walk(node.literals[part], parts, at + 1, params)
    if found.ok?
      return found
    end
  end

  if node.params.empty?
    return error("no route")
  end

  child = node.params[0]
  return walk(child, parts, at + 1, params.put(child.name, part))
end
