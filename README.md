# sysrandom.nim

A simple library to generate random data, using the system's PRNG.

The following sources of randomness are used depending on platform:
- On OpenBSD, [`arc4random(3)`](http://man.openbsd.org/arc4random.3>) is used.
- On Windows, [`RtlGenRandom()`](https://msdn.microsoft.com/en-us/library/windows/desktop/aa387694%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396) is used.
- On recent (>=3.17) versions of the Linux kernel, [`getrandom(2)`](http://man7.org/linux/man-pages/man2/getrandom.2.html) is used.
- On all other posix systems, `/dev/urandmon` is used.

## TODO

- [X] Implement generation of random data on OpenBSD using `arc4random(3)`
- [X] Implement generation of random data on Linux >= 3.17 (using `getrandom(2)`)
- [ ] Implement generation of random data on Windows
- [ ] Implement generation of random data on Linux < 3.17 (kernels without `getrandom(2)`)
- [ ] Implement generation of random data on other posix systems
