# Package

version       = "1.0.0"
author        = "Euan T"
description   = "A simple library to create random strings of data."
license       = "BSD3"

srcDir = "src"

# Dependencies

requires "nim >= 0.16.0"

task docs, "Build documentation":
  exec "nim doc --index:on -o:docs/sysrandom.html src/sysrandom.nim"
