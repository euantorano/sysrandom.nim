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

  proc getRandomBytes*(len: static[int]): array[len, byte] =
    ## Generate an array of random bytes in the range `0` to `0xff`.
    arc4random_buf(addr result[0], len)

  proc getRandom*(): uint32 =
    ## Generate an unpredictable random value in the range `0` to `0xffffffff`.
    result = arc4random()

  proc closeRandom*() = discard
    ## Close the source of randomness.
    ##
    ## On systems such as OpenBSD and Linux (using `getrandom()`), this does nothing.
    ## On Windows and other Posix systems, it releases any resources associated with the generation of random numbers.
elif defined(windows):
  import dynlib, os

  type
    RtlGenRandomFunction = (proc(RandomBuffer: pointer, RandomBufferLength: uint64): bool {.cdecl.})

  var
    Advapi32Handle: LibHandle
    RtlGenRandom: RtlGenRandomFunction

  proc initRtlGenRandom(): RtlGenRandomFunction {.inline.} =
    ## Initialise the RtlGenRandom function if it is none.
    if RtlGenRandom.isNil():
      Advapi32Handle = loadLib("Advapi32.dll")
      RtlGenRandom = cast[RtlGenRandomFunction](checkedSymAddr(Advapi32Handle, "SystemFunction036"))

    result = RtlGenRandom

  proc getRandomBytes*(len: static[int]): array[len, byte] =
    ## Generate an array of random bytes in the range `0` to `0xff`.
    let genRandom = initRtlGenRandom()

    if not genRandom(addr result[0], uint64(len)):
      raiseOsError(osLastError())

  proc getRandom*(): uint32 =
    ## Generate an unpredictable random value in the range `0` to `0xffffffff`.
    let genRandom = initRtlGenRandom()

    if not genRandom(addr result, uint64(sizeof(uint32))):
      raiseOsError(osLastError())

  proc closeRandom*() =
    ## Close the source of randomness.
    ##
    ## On systems such as OpenBSD and Linux (using `getrandom()`), this does nothing.
    ## On Windows and other Posix systems, it releases any resources associated with the generation of random numbers.
    if not RtlGenRandom.isNil():
      unloadLib(Advapi32Handle)
      RtlGenRandom = nil
elif defined(posix):
  import posix, os

  type
    RandomSource = object
      when defined(linux):
        isGetRandomAvailable: bool
      urandomHandle: cint

  var
    isRandomSourceInitialised: bool = false
    randomSource: RandomSource
    S_IFMT {.importc: "S_IFMT", header: "<sys/stat.h>".}: cint
    S_IFCHR {.importc: "S_IFCHR", header: "<sys/stat.h>".}: cint

  when defined(linux):
    var
      SYS_getrandom {.importc: "SYS_getrandom", header: "<syscall.h>".}: clong
      GRND_NONBLOCK {.importc: "GRND_NONBLOCK", header: "<linux/random.h>".}: cint

    proc syscall(number: clong, buf: pointer, buflen: csize, flags: cint): clong {.importc: "syscall", header: "<unistd.h>".}    

  proc checkIsCharacterDevice(statBuffer: Stat): bool =
    ## Check if a device is a character device using the structure initialised by `fstat`.
    result = (int(statBuffer.st_mode) and S_IFMT) == S_IFCHR

  proc openDevUrandom(): cint =
    ## Open the /dev/urandom file, making sure it is a character device.
    result = posix.open("/dev/urandom", O_RDONLY)
    if result == -1:
      isRandomSourceInitialised = false
      raiseOsError(osLastError())

    let existingFcntl = fcntl(result, F_GETFD)
    if existingFcntl == -1:
      isRandomSourceInitialised = false
      discard posix.close(result)
      raiseOsError(osLastError())

    if fcntl(result, F_SETFD, existingFcntl or FD_CLOEXEC) == -1:
      isRandomSourceInitialised = false
      discard posix.close(result)
      raiseOsError(osLastError())

    var statBuffer: Stat
    if fstat(result, statBuffer) == -1:
      isRandomSourceInitialised = false
      discard posix.close(result)
      raiseOsError(osLastError())

    if not checkIsCharacterDevice(statBuffer):
      isRandomSourceInitialised = false
      discard posix.close(result)
      raise newException(OSError, "/dev/urandom is not a valid character device")

  proc initRandomSource(): RandomSource =
    # Initialise the source of randomness.
    when defined(linux):
      result = RandomSource(isGetRandomAvailable: true)

      var data: uint8 = 0'u8
      if syscall(SYS_getrandom, addr data, 1, GRND_NONBLOCK) == -1:
        let error = int32(osLastError())
        if error in {ENOSYS, EPERM}:
          # The getrandom syscall is not available, so open the /dev/urandom file
          result.isGetRandomAvailable = false
          result.urandomHandle = openDevUrandom()
        else:
          raiseOsError(osLastError())
    else:
      result = RandomSource(urandomHandle: openDevUrandom())

  proc getRandomSource(): RandomSource =
    ## Get the random source to use in order to get random data.
    if not isRandomSourceInitialised:
      randomSource = initRandomSource()
      isRandomSourceInitialised = true

    result = randomSource

  proc getRandomBytes*(len: static[int]): array[len, byte] =
    ## Generate an array of random bytes in the range `0` to `0xff`.
    let source = getRandomSource()

    var
      data: array[len, byte]
      totalRead: int = 0
      numRead: int

    when defined(linux):
      if source.isGetRandomAvailable:
        ## Using a fairly recent Linux kernel with the `getrandom` syscall, so use that.
        while totalRead < len:
          numRead = syscall(SYS_getrandom, addr data[totalRead], len - totalRead, GRND_NONBLOCK)
          if numRead == -1:
            raiseOsError(osLastError())

          inc(totalRead, numRead)

        return data

    while totalRead < len:
      numRead = posix.read(source.urandomHandle, addr data[totalRead], len - totalRead)
      if numRead == -1:
        raiseOsError(osLastError())
        
      inc(totalRead, numRead)

    return data

  proc getRandom*(): uint32 =
    ## Generate an unpredictable random value in the range `0` to `0xffffffff`.
    let source = getRandomSource()

    var data: uint32
    when defined(linux):
      if source.isGetRandomAvailable:
        if syscall(SYS_getrandom, addr data, sizeof(uint32), GRND_NONBLOCK) == -1:
          raiseOsError(osLastError())

        return data

    if posix.read(source.urandomHandle, addr data, sizeof(uint32)) == -1:
      raiseOsError(osLastError())

    return data

  proc closeRandom*() =
    ## Close the source of randomness.
    ##
    ## On systems such as OpenBSD and Linux (using `getrandom()`), this does nothing.
    ## On Windows and other Posix systems, it releases any resources associated with the generation of random numbers.
    if isRandomSourceInitialised:
      isRandomSourceInitialised = false
      when defined(linux):
        if not randomSource.isGetRandomAvailable:
          discard posix.close(randomSource.urandomHandle)
      else:
        discard posix.close(randomSource.urandomHandle)
else:
  {.error: "Unsupported platform".}

proc getRandomString*(len: static[int]): string =
  ## Create a random string with the given number of btes.
  ##
  ## This uses `getRandomBytes` under the hood and Base 64 encodes the resulting arrays.
  let buff = getRandomBytes(len)
  result = encode(buff)

when isMainModule:
  proc main() =
    defer: closeRandom()

    echo "Generating 5 random unisgned integers:"

    for i in 0..4:
      echo "Random int: ", getRandom()

    let randomBytes = getRandomBytes(5)
    echo "\nGenerating 5 random bytes: ", repr(randomBytes)

    echo "\nGenerating 5 random 256 bit strings:"

    for i in 0..4:
      echo "Random string: ", getRandomString(32)

  main()
