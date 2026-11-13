## The routes as a tree of path segments, as in the compiled router of Falcon. A node holds the routes that end at it
## (a handler for each method), its literal children by name, and at most one param child. A request walks the tree
## once, so the work typically depends on the length of the path and not on the number of routes. (When a literal
## branch fails deep, the walk goes back to a param branch, so a hostile path can visit more branches; the most it
## can visit is bounded by the size of the tree.)

import Pattern from "pattern"
import {Handler} from "conn"

## A step of the tree. `name` is the param name of a param child (the node itself has none: it is the child's).
struct Node
  literals: Map[String, Node]
  params: List[Node]
  name: String
  handlers: Map[String, Handler]
end

## The node that a route found, with the params on the way to it.
struct Found
  node: Node
  params: Map[String, String]
end

## A tree with no route.
def empty() -> Node = Node(literals: {}, params: [], name: "", handlers: {})

## Adds the route to the tree. It is an `error` when the same method and pattern are already there (a trailing or a
## double slash does not make another pattern), or when the pattern has another param name than the routes already in
## the tree at the same place: `/users/:id` and `/users/:name/posts` cannot both be.
def add(root: Node, method: String, pattern: String, handler: Handler) -> Result[Node]
  insert(root, Pattern.segments(pattern), Route(method: method, pattern: pattern, handler: handler))
end

## The node that holds the route of `path`, with the params. A literal segment is tried before the param of the same
## place, and when the literal branch has no route to the end the walk goes back to the param. `error` when no route
## has this path (the method is not looked at here).
def find(root: Node, path: String) -> Result[Found] = walk(root, Pattern.segments(path), 0, {})

private

# The route being added, so that its parts travel together down the tree.
struct Route
  method: String
  pattern: String
  handler: Handler
end

def insert(node: Node, parts: List[String], route: Route) -> Result[Node]
  if parts.empty?
    return error("bond: the route #{route.method} #{route.pattern} is added twice") if node.handlers.key?(route.method)

    return ok(node.with(handlers: node.handlers.put(route.method, route.handler)))
  end

  part = parts[0]
  rest = parts.drop(1)
  return insert_param(node, part.slice(1, part.length - 1), rest, route) if part.start_with?(":")

  child = node.literals.get(part, empty())
  updated = try insert(child, rest, route)
  ok(node.with(literals: node.literals.put(part, updated)))
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
  ok(node.with(params: [updated]))
end

def walk(node: Node, parts: List[String], at: Int, params: Map[String, String]) -> Result[Found]
  if at == parts.size
    return error("no route") if node.handlers.empty?

    return ok(Found(node: node, params: params))
  end

  part = parts[at]
  if node.literals.key?(part)
    found = walk(node.literals[part], parts, at + 1, params)
    return found if found.ok?
  end

  return error("no route") if node.params.empty?

  child = node.params[0]
  walk(child, parts, at + 1, params.put(child.name, part))
end
