# 0.14.0.0

Work-In-Progress intermediate release in preperation of splitting this package.

This compiles and the tests run, but the code really sucks!


# 0.11.4.0

* Rename `AacMp4StreamConfig` to `AacInitSegment`
* Rename `InitSegment` to `BinaryAacInitSegment`
* Extract `AacInitSegment` and `BinaryAacInitSegment` from module `AudioStreaming` into a new
  module: `Data.ByteString.Mp4.AacInitSegment`
* Fix unit test `Mp4AudioSampleEntrySpec`
* Add CHANGELOG.md
* Switch to stackage lts-8.6
