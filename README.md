# sysrandom.nim [![CircleCI](https://circleci.com/gh/euantorano/sysrandom.nim.svg?style=svg)](https://circleci.com/gh/euantorano/sysrandom.nim)

A simple library to generate random data, using the system's PRNG.

The following sources of randomness are used depending on platform:
- On OpenBSD, [`arc4random(3)`](http://man.openbsd.org/arc4random.3) is used.
- On Windows, [`RtlGenRandom()`](https://msdn.microsoft.com/en-us/library/windows/desktop/aa387694%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396) is used.
- On recent (>=3.17) versions of the Linux kernel, [`getrandom(2)`](http://man7.org/linux/man-pages/man2/getrandom.2.html) is used.
- On all other posix systems, `/dev/urandom` is used.

## Installation

`sysrandom` can be installed using Nimble:

```
nimble install sysrandom
```

Or add the following to your .nimble file:

```
# Dependencies

requires "sysrandom >= 1.1.0"
```

## [API Documentation](https://htmlpreview.github.io/?https://github.com/euantorano/sysrandom.nim/blob/master/docs/sysrandom.html)

## Usage

```nim
import sysrandom

## Make sure to close the `/dev/urandom` file on posix or close the DLL handle on Windows after you're finished generating random data
defer: closeRandom()

## Fill a buffer with x random bytes
var buffer = newSeq[byte](20)
getRandomBytes(addr buffer[0], len(buffer))

## Create an array of 10 random bytes (`array[10, byte]`)
let randomBytes = getRandomBytes(10)
echo "Generating 10 random bytes: ", repr(randomBytes)

## Get a random unsigned 32 bit integer (`uint32`) in the range 0..0xffffffff
let randomUint32 = getRandom()
echo "Random integer: ", randomUint32

## Generate a random string based upon a 32 byte array of random values, base 64 encoded
let randomString = getRandomString(32)
echo "Random string: ", randomString
```
