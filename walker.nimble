# Package

version       = "0.1.0"
author        = "zedeus"
description   = "Random walk image tracer"
license       = "MIT"
srcDir        = "src"
bin           = @["walker"]



# Dependencies

requires "nim >= 1.0", "flippy", "chroma", "vmath", "cligen", "nuuid"
