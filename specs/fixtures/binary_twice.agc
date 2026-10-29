## A program that asks twice for a file that is not text. The notice about binary files is written once.

import Bond from "../../bond"
import Testing from "../../testing"

def main() -> Void
  app = Bond.app() |> Bond.static("/assets", "fixtures/public")
  for i in 0...2
    puts(Testing.request(app, "GET", "/assets/pixel.png").status)
  end
end
