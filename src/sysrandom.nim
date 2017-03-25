## A simple library to generate random data, using the system's PRNG.
##
## The following sources of randomness are used depending on platform:
## - On OpenBSD, `arc4random(3)<http://man.openbsd.org/arc4random.3>`_ is used.
## - On Windows, `RtlGenRandom()<https://msdn.microsoft.com/en-us/library/windows/desktop/aa387694%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396>`_ is used.
## - On recent (>=3.17) versions of the Linux kernel, `getrandom(2)<http://man7.org/linux/man-pages/man2/getrandom.2.html>`_ is used.
## - On all other posix systems, `/dev/urandmon` is used.

import base64

when defined(openbsd):
  proc arc4random(): uint32 {.importc: "arc4random", header: "<stdlib.h>".}

  proc arc4random_uniform(upperBound: uint32): uint32 {.importc: "arc4random_uniform", header: "<stdlib.h>".}

  proc arc4random_buf(buf: pointer, nbytes: csize) {.importc: "arc4random_buf", header: "<stdlib.h>".}

  proc getRandomBytes*(len: static[int]): array[len, byte] {.raises: [OSError].} =
    ## Generate an array of random bytes in the range `0` to `0xff`.
    arc4random_buf(addr result[0], len)

  proc getRandom*(): uint32 {.raises: [OSError].} =
    ## Generate an unpredictable random value in the range `0` to `0xffffffff`.
    result = arc4random()

  proc getRandomString*(len: static[int]): string {.raises: [OSError].} =
    ## Create a random string with the given number of btes.
    ##
    ## This uses `getRandomBytes` under the hood and Base 64 encodes the resulting arrays.
    let buff = getRandomBytes(len)
    result = encode(buff)
elif defined(linux):
  import os

  proc syscall(number: clong, buf: pointer, buflen: csize, flags: uint32): clong {.importc: "syscall", header: "<unistd.h>".}

  var SYS_getrandom {.importc: "SYS_getrandom", header: "<syscall.h>".}: clong

  proc getRandomBytes*(len: static[int]): array[len, byte] {.raises: [OSError].} =
    ## Generate an array of random bytes in the range `0` to `0xff`.
    var
      totalRead: int = 0
      ret: int

    while totalRead < len:
      ret = syscall(SYS_getrandom, addr result[totalRead], len - totalRead, 0)

      if ret == -1:
        raiseOsError(osLastError())

      inc(totalRead, ret)

  proc getRandom*(): uint32 {.raises: [OSError].} =
    ## Generate an unpredictable random value in the range `0` to `0xffffffff`.
    if syscall(SYS_getrandom, addr result, sizeof(uint32), 0) == -1:
      raiseOsError(osLastError())

  proc getRandomString*(len: static[int]): string {.raises: [OSError].} =
    ## Create a random string with the given number of btes.
    ##
    ## This uses `getRandomBytes` under the hood and Base 64 encodes the resulting arrays.
    let buff = getRandomBytes(len)
    result = encode(buff)
else:
  {.error: "Unsupported platform".}

when isMainModule:
  proc main() =
    echo "Generating 5 random unisgned integers:"

    for i in 0..4:
      echo "Random int: ", getRandom()

    echo "\nGenerating 5 random bytes:"
    let randomBytes = getRandomBytes(5)

    for i in low(randomBytes)..high(randomBytes):
      echo "Random byte: ", randomBytes[i]

    echo "\nGenerating 5 random 256 bit strings:"

    for i in 0..4:
      echo "Random string: ", getRandomString(32)
