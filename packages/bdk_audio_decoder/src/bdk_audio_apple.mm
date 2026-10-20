#include "bdk_audio_platform.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMedia/CoreMedia.h>
#include <unistd.h>

// Offline resource-loader reads only the already-open descriptor's bounded
// range.
@interface BdkOfflineAudioLoader : NSObject <AVAssetResourceLoaderDelegate>
@property(nonatomic) int descriptor;
@property(nonatomic) int64_t length;
@property(nonatomic) int64_t startOffset;
@property(nonatomic) BOOL closed;
@property(nonatomic, strong) NSString *contentType;
@end
@implementation BdkOfflineAudioLoader
- (BOOL)resourceLoader:(AVAssetResourceLoader *)loader
    shouldWaitForLoadingOfRequestedResource:
        (AVAssetResourceLoadingRequest *)request {
  (void)loader;
  if (self.closed) {
    [request finishLoadingWithError:[NSError errorWithDomain:@"BDKAudio"
                                                        code:2
                                                    userInfo:nil]];
    return YES;
  }
  request.contentInformationRequest.contentType = self.contentType;
  request.contentInformationRequest.contentLength = self.length;
  request.contentInformationRequest.byteRangeAccessSupported = YES;
  auto *data = request.dataRequest;
  if (data) {
    int64_t start = std::max<int64_t>(data.currentOffset, data.requestedOffset);
    if (start < 0 || data.requestedOffset < 0) {
      [request finishLoadingWithError:[NSError errorWithDomain:@"BDKAudio"
                                                          code:6
                                                      userInfo:nil]];
      return YES;
    }
    int64_t end = self.length;
    if (!data.requestsAllDataToEndOfResource && data.requestedLength >= 0 &&
        data.requestedLength <= INT64_MAX - data.requestedOffset)
      end = std::min<int64_t>(end, data.requestedOffset + data.requestedLength);
    if (start < 0 || data.requestedOffset < 0) {
      [request finishLoadingWithError:[NSError errorWithDomain:@"BDKAudio"
                                                          code:6
                                                      userInfo:nil]];
      return YES;
    }
    if (start >= self.length) {
      [request finishLoading];
      return YES;
    }
    if (end < start) {
      [request finishLoadingWithError:[NSError errorWithDomain:@"BDKAudio"
                                                          code:6
                                                      userInfo:nil]];
      return YES;
    }
    uint8_t buffer[65536];
    while (start < end) {
      size_t count = size_t(std::min<int64_t>(sizeof buffer, end - start));
      auto got = pread(self.descriptor, buffer, count,
                       off_t(self.startOffset + start));
      if (got != ssize_t(count)) {
        [request finishLoadingWithError:[NSError errorWithDomain:@"BDKAudio"
                                                            code:2
                                                        userInfo:nil]];
        return YES;
      }
      [data respondWithData:[NSData dataWithBytes:buffer length:count]];
      start += count;
    }
  }
  [request finishLoading];
  return YES;
}
@end

namespace {
struct Asset {
  __strong AVURLAsset *asset = nil;
  __strong AVAssetTrack *track = nil;
  __strong BdkOfflineAudioLoader *loader = nil;
  __strong dispatch_queue_t queue = nil;
  ~Asset() {
    [asset cancelLoading];
    [asset.resourceLoader setDelegate:nil queue:nil];
    if (queue)
      dispatch_sync(queue, ^{
        loader.closed = YES;
      });
  }
  int open(BdkAudioFile file, bdk_audio_info &info) {
    NSString *name = [NSString stringWithUTF8String:file.name];
    if (!name)
      return BDK_AUDIO_INVALID_UTF8;
    auto prefix = bdk_adts_offset(file);
    if (prefix != UINT64_MAX) {
      file.offset += prefix;
      file.size -= prefix;
    }
    uint8_t magic[4]{};
    pread(fileno(file.file), magic, 4, off_t(file.offset));
    NSString *extension = prefix != UINT64_MAX             ? @"aac"
                          : !std::memcmp(magic, "OggS", 4) ? @"ogg"
                                                           : @"m4a";
    loader = [BdkOfflineAudioLoader new];
    loader.descriptor = fileno(file.file);
    loader.length = int64_t(file.size);
    loader.startOffset = int64_t(file.offset);
    loader.contentType =
        [extension isEqualToString:@"aac"]   ? @"public.aac-audio"
        : [extension isEqualToString:@"ogg"] ? @"org.xiph.ogg"
                                             : @"public.mpeg-4-audio";
    queue = dispatch_queue_create("bdk.audio.offline", DISPATCH_QUEUE_SERIAL);
    NSString *url =
        [NSString stringWithFormat:@"bdk-offline://source/audio.%@",
                                   extension.length ? extension : @"m4a"];
    asset = [AVURLAsset
        URLAssetWithURL:[NSURL URLWithString:url]
                options:@{
                  AVURLAssetPreferPreciseDurationAndTimingKey : @YES,
                  AVURLAssetReferenceRestrictionsKey :
                      @(AVAssetReferenceRestrictionForbidAll)
                }];
    [asset.resourceLoader setDelegate:loader queue:queue];
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[ @"tracks", @"duration" ]
                         completionHandler:^{
                           dispatch_semaphore_signal(ready);
                         }];
    if (dispatch_semaphore_wait(
            ready, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC)) != 0)
      return BDK_AUDIO_DECODE_FAILED;
    if ([asset statusOfValueForKey:@"tracks"
                             error:nil] != AVKeyValueStatusLoaded ||
        [asset statusOfValueForKey:@"duration"
                             error:nil] != AVKeyValueStatusLoaded ||
        asset.hasProtectedContent)
      return BDK_AUDIO_UNSUPPORTED;
    track = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!track || !track.formatDescriptions.count)
      return BDK_AUDIO_UNSUPPORTED;
    auto description = (__bridge CMAudioFormatDescriptionRef)
                           track.formatDescriptions.firstObject;
    auto *format =
        CMAudioFormatDescriptionGetStreamBasicDescription(description);
    double duration = CMTimeGetSeconds(track.timeRange.duration);
    if (!format || !std::isfinite(duration) || duration <= 0 ||
        !std::isfinite(format->mSampleRate) || format->mSampleRate < 1000 ||
        format->mSampleRate > 192000 ||
        !std::isfinite(CMTimeGetSeconds(track.timeRange.start)))
      return BDK_AUDIO_UNSUPPORTED;
    long double frames =
        static_cast<long double>(duration) * format->mSampleRate;
    if (frames < 1 || frames > INT64_MAX)
      return BDK_AUDIO_RANGE;
    info = {uint32_t(std::llround(format->mSampleRate)),
            format->mChannelsPerFrame, uint64_t(std::llround(frames))};
    return bdk_validate_info(info);
  }
};
} // namespace
int bdk_platform_probe(BdkAudioFile file, bdk_audio_info &info) {
  @autoreleasepool {
    Asset value;
    return value.open(file, info);
  }
}
int bdk_platform_decode(BdkAudioFile file, uint32_t rate, uint64_t start,
                        uint32_t count, int16_t *output) {
  @autoreleasepool {
    Asset value;
    bdk_audio_info info{};
    auto code = value.open(file, info);
    if (code)
      return code;
    BdkPcmWindow window;
    code = window.init(info, rate, start, count);
    if (code)
      return code;
    NSError *error = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:value.asset
                                                           error:&error];
    if (!reader)
      return BDK_AUDIO_UNSUPPORTED;
    NSDictionary *settings = @{
      AVFormatIDKey : @(kAudioFormatLinearPCM),
      AVSampleRateKey : @(info.sample_rate),
      AVNumberOfChannelsKey : @(info.channels),
      AVLinearPCMBitDepthKey : @32,
      AVLinearPCMIsFloatKey : @YES,
      AVLinearPCMIsBigEndianKey : @NO,
      AVLinearPCMIsNonInterleaved : @NO
    };
    AVAssetReaderAudioMixOutput *pcm = [AVAssetReaderAudioMixOutput
        audioMixOutputWithAudioTracks:@[ value.track ]
                        audioSettings:settings];
    pcm.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:pcm])
      return BDK_AUDIO_UNSUPPORTED;
    [reader addOutput:pcm];
    uint64_t first = window.firstSourceFrame(),
             before = first > info.sample_rate ? first - info.sample_rate : 0;
    auto trackStart=value.track.timeRange.start;
    auto selectedStart=CMTimeAdd(trackStart,CMTimeMake(int64_t(before),info.sample_rate));
    auto trackEnd=CMTimeRangeGetEnd(value.track.timeRange);
    reader.timeRange=CMTimeRangeMake(selectedStart,CMTimeSubtract(trackEnd,selectedStart));
    if (![reader startReading])
      return BDK_AUDIO_DECODE_FAILED;
    while (!window.complete()) {
      CMSampleBufferRef sample = [pcm copyNextSampleBuffer];
      if (!sample)
        break;
      auto description = CMSampleBufferGetFormatDescription(sample);
      auto *format =
          CMAudioFormatDescriptionGetStreamBasicDescription(description);
      CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
      size_t length = block ? CMBlockBufferGetDataLength(block) : 0;
      auto frames = CMSampleBufferGetNumSamples(sample);
      double time = CMTimeGetSeconds(CMTimeSubtract(
          CMSampleBufferGetPresentationTimeStamp(sample),trackStart));
      if (!format || format->mFormatID != kAudioFormatLinearPCM ||
          !(format->mFormatFlags & kAudioFormatFlagIsFloat) ||
          (format->mFormatFlags &
           (kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsBigEndian)) ||
          format->mBitsPerChannel != 32 ||
          format->mChannelsPerFrame != info.channels ||
          format->mSampleRate != info.sample_rate || !std::isfinite(time) ||
          frames < 0 || length > 4 * 1024 * 1024 ||
          uint64_t(frames) * info.channels * 4 != length) {
        CFRelease(sample);
        [reader cancelReading];
        return BDK_AUDIO_DECODE_FAILED;
      }
      std::vector<uint8_t> bytes(length);
      if (CMBlockBufferCopyDataBytes(block, 0, length, bytes.data()) !=
          kCMBlockBufferNoErr) {
        CFRelease(sample);
        [reader cancelReading];
        return BDK_AUDIO_DECODE_FAILED;
      }
      auto stamp = int64_t(
          std::llround(static_cast<long double>(time) * info.sample_rate));
      code =
          window.add(bytes.data(), size_t(frames), info.channels, true, stamp);
      CFRelease(sample);
      if (code) {
        [reader cancelReading];
        return code;
      }
    }
    if (reader.status == AVAssetReaderStatusFailed) {
      [reader cancelReading];
      return BDK_AUDIO_DECODE_FAILED;
    }
    [reader cancelReading];
    return window.finish(output);
  }
}
