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
    ## On other Posix systems, it releases any resources associated with the generation of random numbers.
elif defined(windows):
  import os

  proc RtlGenRandom(RandomBuffer: pointer, RandomBufferLength: uint64): bool {.cdecl, dynlib: "Advapi32.dll", importc: "SystemFunction036".}

  proc getRandomBytes*(len: static[int]): array[len, byte] =
    ## Generate an array of random bytes in the range `0` to `0xff`.
    if not RtlGenRandom(addr result[0], uint64(len)):
      raiseOsError(osLastError())

  proc getRandom*(): uint32 =
    ## Generate an unpredictable random value in the range `0` to `0xffffffff`.
    if not RtlGenRandom(addr result, uint64(sizeof(uint32))):
      raiseOsError(osLastError())

  proc closeRandom*() = discard
    ## Close the source of randomness.
    ##
    ## On systems such as OpenBSD and Linux (using `getrandom()`), this does nothing.
    ## On other Posix systems, it releases any resources associated with the generation of random numbers.
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

    proc syscall(number: clong, buf: pointer, buflen: csize, flags: cint): clong {.importc: "syscall", header: "<unistd.h>".}   
    
    proc safeSyscall(buffer: pointer, size: int) =
      var
        readNumberBytes: int
        mutBuf: pointer = buffer
        mutSize = size
        lastError: OSErrorCode

      while mutSize > 0:
        readNumberBytes = syscall(SYS_getrandom, mutBuf, mutSize, 0)
        lastError = osLastError()
        while readNumberBytes < 0 and (lastError == OSErrorCode(EINTR) or lastError == OSErrorCode(EAGAIN)):
          readNumberBytes = syscall(SYS_getrandom, mutBuf, mutSize, 0)
          lastError = osLastError()

        if readNumberBytes < 0:
          raiseOsError(osLastError())

        if readNumberBytes == 0:
          break

        dec(mutSize, readNumberBytes)

        if mutSize == 0:
          break

        mutBuf = cast[pointer](cast[int](mutBuf) + readNumberBytes)

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
      if syscall(SYS_getrandom, addr data, 1, 0) == -1:
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

  proc safeRead(fileHandle: cint, buffer: pointer, size: int) =
    var
      readNumberBytes: int
      mutBuf: pointer = buffer
      mutSize = size
      lastError: OSErrorCode

    while mutSize > 0:
      readNumberBytes = posix.read(fileHandle, mutBuf, mutSize)
      lastError = osLastError()
      while readNumberBytes < 0 and (lastError == OSErrorCode(EINTR) or lastError == OSErrorCode(EAGAIN)):
        readNumberBytes = posix.read(fileHandle, mutBuf, mutSize)
        lastError = osLastError()

      if readNumberBytes < 0:
        raiseOsError(osLastError())

      if readNumberBytes == 0:
        break

      dec(mutSize, readNumberBytes)

      if mutSize == 0:
        break

      mutBuf = cast[pointer](cast[int](mutBuf) + readNumberBytes)

  proc getRandomBytes*(len: static[int]): array[len, byte] =
    ## Generate an array of random bytes in the range `0` to `0xff`.
    let source = getRandomSource()

    when defined(linux):
      if source.isGetRandomAvailable:
        ## Using a fairly recent Linux kernel with the `getrandom` syscall, so use that.
        safeSyscall(addr result, len)
        return result

    safeRead(source.urandomHandle, addr result[0], len)

  proc getRandom*(): uint32 =
    ## Generate an unpredictable random value in the range `0` to `0xffffffff`.
    let source = getRandomSource()

    when defined(linux):
      if source.isGetRandomAvailable:
        ## Using a fairly recent Linux kernel with the `getrandom` syscall, so use that.
        safeSyscall(addr result, sizeof(uint32))
        return result

    safeRead(source.urandomHandle, addr result, sizeof(uint32))

  proc closeRandom*() =
    ## Close the source of randomness.
    ##
    ## On systems such as OpenBSD and Linux (using `getrandom()`), this does nothing.
    ## On other Posix systems, it releases any resources associated with the generation of random numbers.
    if isRandomSourceInitialised:
      isRandomSourceInitialised = false
      when defined(linux):
        if not randomSource.isGetRandomAvailable:
          discard posix.close(randomSource.urandomHandle)
      else:
        discard posix.close(randomSource.urandomHandle)
else:
  {.error: "Unsupported platform".}

proc getRandomNumber*[T: SomeNumber](): T =
  ## Get a random number of any type.
  let bytes = getRandomBytes(sizeof(T))
  result = cast[T](bytes)

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
      echo "Random unsigned int: ", getRandom()

    echo "\nTrying the generic getRandomNumber:"

    let randomInt32: int32 = getRandomNumber[int32]()
    echo "Random 32 bit integer: ", randomInt32

    let randomInt64: int64 = getRandomNumber[int64]()
    echo "Random 64 bit integer: ", randomInt64

    let randomUint64: uint64 = getRandomNumber[uint64]()
    echo "Random 64 bit unsigned integer: ", randomUint64

    let randomUint8: uint8 = getRandomNumber[uint8]()
    echo "Random 8 bit unsigned integer: ", randomUint8

    let randomBytes = getRandomBytes(5)
    echo "\nGenerating 5 random bytes: ", repr(randomBytes)

    echo "\nGenerating 5 random 256 bit strings:"

    for i in 0..4:
      echo "Random string: ", getRandomString(32)

  main()
