import sysrandom, unittest

# TODO: These tests are pretty naive and could probably be improved

suite "sysrandom tests":
  test "generate 100 random numbers, making sure each doesn't equal the last":
    var
      lastRandom: uint32
      currentRandom: uint32 = getRandom()

    for i in 0..<100:
      lastRandom = currentRandom
      currentRandom = getRandom()

      check currentRandom != lastRandom

  test "fill an array of 10 random values":
    var arr: array[10, byte]
    getRandomBytes(addr arr[0], len(arr))

    for i in 1..high(arr):
      check arr[i] != arr[i-1]

  test "create an array of 10 random values":
    let arr = getRandomBytes(10)

    for i in 1..high(arr):
      check arr[i] != arr[i-1]

  test "create a seq of 10 random values":
    let
      len = 10
      s: seq[byte] = getRandomBytes(len)

    for i in 1..high(s):
      check s[i] != s[i-1]

  test "create 10 random strings of static length":
    var
      lastRandom: string
      currentRandom: string = getRandomString(32)

    for i in 0..<100:
      lastRandom = currentRandom
      currentRandom = getRandomString(32)

      check currentRandom != lastRandom

  test "create 10 random strings of runtime length":
    var
      len: int = 64
      lastRandom: string
      currentRandom: string = getRandomString(len)

    for i in 0..<100:
      lastRandom = currentRandom
      currentRandom = getRandomString(len)

      check currentRandom != lastRandom

  test "generate 100 random numbers between 0 and 100":
    var rand: uint32
    for i in 0..<100:
      rand = getRandom(100)

      check rand < 100



  closeRandom()
