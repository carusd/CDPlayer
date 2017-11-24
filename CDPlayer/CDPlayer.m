//
//  CDPlayer.m
//  CDPlayer
//
//  Created by carusd on 2016/12/2.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDPlayer.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <AVFoundation/AVFoundation.h>
#import "CDVideoDownloadTask.h"
#import "CDVideoDownloadMegaManager.h"
#import "CDVideoDownloadManager.h"
#import "CDVideoBlock.h"
#import "NSString+CDFilePath.h"

NSString * const CDPlayerDidSeekToPositionNotif = @"CDPlayerDidSeekToPositionNotif";
NSString * const CDPlayerItemDidPlayToEndTimeNotif = @"CDPlayerItemDidPlayToEndTimeNotif";

@interface CDPlayerItem : AVPlayerItem



@end

@implementation CDPlayerItem

- (void)dealloc {
    NSLog(@"CDPlayerItem what theeeeeeeeeee?");
}

@end


@interface CDPlayerInternal : AVPlayer

@end

@implementation CDPlayerInternal

- (void)dealloc {
    NSLog(@"CDPlayerInternal hmmmmmmmmmm?");
}

- (void)play {
    [super play];
    
}

- (void)setRate:(float)rate {
    [super setRate:rate];
    
}

@end

@interface CDPlayer()<AVAssetResourceLoaderDelegate>

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVURLAsset *asset;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic) CDPlayerState state;
@property (nonatomic, strong) NSError *error;
@property (nonatomic) BOOL fromLocalFile;
@property (nonatomic, strong) id<CDVideoInfoProvider> provider;
@property (nonatomic, strong) CDVideoDownloadTask *task;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) NSMutableArray<AVAssetResourceLoadingRequest *> *requests;
@property (nonatomic) BOOL shouldPushOffset;
@property (nonatomic) double shouldSeekToPosition;
@property (nonatomic, strong) dispatch_queue_t preparing_q;
@property (nonatomic, strong) CADisplayLink *displayLink;

@end

@implementation CDPlayer

+ (NSString *)dispatcherTag {
    return @"player";
}

+ (id<CDVideoDownloadTaskDispatcher>)dispatcher {
    CDVideoDownloadManager *manager = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:[CDPlayer dispatcherTag] class:nil];
    manager.maxConcurrentNum = 1;
    return manager;;
}


- (void)dealloc {
    
    [_task pause];
    
    [_fileHandle closeFile];
    [_asset.resourceLoader setDelegate:nil queue:dispatch_get_main_queue()];
    
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_playerItem removeObserver:self forKeyPath:@"status" context:NULL];
    [_playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty" context:NULL];
    [_playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:NULL];
    
    
    
    NSLog(@"deallc player for %@", _provider);
}



- (id)initWithInfo:(id<CDVideoInfoProvider>)infoProvider {
    self = [super init];
    if (self) {
        
        [self setupWithInfoProvider:infoProvider];
        
        
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskDidHasNewBlock:) name:CDVideoDownloadTaskDidHasNewBlockNotif object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskStateDidChanged:) name:CDVideoDownloadStateDidChangedNotif object:nil];
    }
    
    return self;
}


- (void)setupPlayer {
    if (!self.player) {
        self.playerItem = [CDPlayerItem playerItemWithAsset:self.asset];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidStalled:) name:AVPlayerItemPlaybackStalledNotification object:self.playerItem];
        
        self.requests = [NSMutableArray array];
        
        [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
        [self.playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:NULL];
        [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:NULL];
        
        
        self.player = [CDPlayerInternal playerWithPlayerItem:self.playerItem];
        
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 10) {
            self.player.automaticallyWaitsToMinimizeStalling = YES;
        }
        
        self.state = CDPlayerStateStandby;
        
    }
    
}

- (void)setupWithInfoProvider:(id<CDVideoInfoProvider>)infoProvider {
    self.state = CDPlayerStatePreparing;
    
    self.provider = infoProvider;
    
    NSString *localURLPath = [NSString toAbsolute:infoProvider.localURLPath];
    
    if (infoProvider.completelyLoaded) {
        self.asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:localURLPath]];
        self.fromLocalFile = YES;
        
        self.preparing_q = dispatch_queue_create("com.carusd.player.preparing", DISPATCH_QUEUE_CONCURRENT);
        
        __weak CDPlayer *wself = self;
        [self.asset loadValuesAsynchronouslyForKeys:@[@"duration"] completionHandler:^{
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *e = nil;
                AVKeyValueStatus status = [wself.asset statusOfValueForKey:@"duration" error:&e];
                if (AVKeyValueStatusLoaded == status) {
                    
                    [wself setupPlayer];
                } else if (AVKeyValueStatusFailed == status) {
                    wself.error = e;
                    wself.state = CDPlayerStateError;
                } else if (AVKeyValueStatusUnknown == status) {
                    wself.error = [[NSError alloc] initWithDomain:@"com.carusd.player" code:status userInfo:@{NSLocalizedFailureReasonErrorKey: @"load key unknown error"}];
                    wself.state = CDPlayerStateError;
                } else if (AVKeyValueStatusCancelled == status) {
                    wself.error = [[NSError alloc] initWithDomain:@"com.carusd.player" code:status userInfo:@{NSLocalizedFailureReasonErrorKey: @"load key cancelled"}];
                    wself.state = CDPlayerStateError;
                }
            });
            
        }];
    } else {
        
        self.task = [[CDPlayer dispatcher] makeTaskWithInfo:infoProvider];
        self.task.player = self;
        NSURLComponents *videoURLComponents = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:self.task.videoURLPath] resolvingAgainstBaseURL:NO];
        videoURLComponents.scheme = @"streaming";
        self.asset = [AVURLAsset assetWithURL:videoURLComponents.URL];
        [self.asset.resourceLoader setDelegate:self queue:dispatch_get_main_queue()];

        
        NSError *e = nil;
        self.fileHandle = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:localURLPath] error:&e];
        
        [self setupPlayer];
        
    }
}

- (void)stopDisplayLink {
    self.displayLink.paused = YES;
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)startDisplayLink {
    [self stopDisplayLink];
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handlePlayingDisplayLink)];
    [self.displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    self.displayLink.paused = NO;
}

- (void)handlePlayingDisplayLink {
//    NSLog(@"uuuuuuuu  %f", CMTimebaseGetRate(self.playerItem.timebase));
    if (CMTimebaseGetRate(self.playerItem.timebase) > 0) {
        
        if (CDPlayerStateBuffering == self.state) {
            self.state = CDPlayerStatePlaying;
        }
        
    } else {
//        if (CDPlayerStatePlaying == self.state && CDVideoDownloadStateLoading == self.task.state) {
//            self.state = CDPlayerStateBuffering;
//        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    
    if ([keyPath isEqualToString:@"status"]) {
        switch (self.playerItem.status) {
            case AVPlayerItemStatusReadyToPlay:
                
                if (CDPlayerStateBuffering == self.state) {
                    
                    if (self.playerItem.playbackLikelyToKeepUp) {
                        self.state = CDPlayerStatePlaying;
                        [self.player play];
                    }
                } else if (CDPlayerStatePause == self.state || CDPlayerStateStop == self.state) {
                    [self.player pause];
                }
                break;
            case AVPlayerItemStatusFailed:
                NSLog(@"lllllllllllll  %@", self.playerItem.error);
//                self.error = self.playerItem.error;
//                self.state = CDPlayerStateError;
                break;
            default:
                break;
                
            
        }
    } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
        if (!self.playerItem.playbackLikelyToKeepUp) {
            if (CDPlayerStatePlaying == self.state && CDVideoDownloadStateLoading == self.task.state) {
                self.state = CDPlayerStateBuffering;
                NSLog(@"ppppppppppp");
            }
        } else {
            if (CDPlayerStateBuffering == self.state) {
                [self.player play];
                self.state =  CDPlayerStatePlaying;
            }
            
        }
        
    } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
        NSLog(@"playbackBufferEmpty");
        if (self.task.state == CDVideoDownloadStateError) {
            self.error = self.task.error;
            self.state = CDPlayerStateError;
//            // 下载途中失败之后，播放器还是继续在播放，这个时候不应该就马上显示错误
//            // 而是继续播放，直到playbackBufferEmpty为真，这个时候还是不应该马上
//            // 显示错误。而是尝试重新下载，重新下载还是失败，在handleTaskStateDidChanged
//            // 中处理
//            [self.task load];
//            self.state = CDPlayerStateBuffering;
        } else if (self.task.state == CDVideoDownloadStateLoading) {
            if (self.state == CDPlayerStatePlaying) {
                self.state = CDPlayerStateBuffering;
                NSLog(@"eeeeeeeeee");
            }
            
        }
        
    }
}



#pragma control
- (CGFloat)playProgress {
    CGFloat duration = CMTimeGetSeconds(self.playerItem.duration);
    if (duration == 0) {
        return 0;
    } else {
        return CMTimeGetSeconds(self.playerItem.currentTime) / CMTimeGetSeconds(self.playerItem.duration);
    }
    
}

- (void)_play {
    if (CDPlayerStatePlaying == self.state || CDPlayerStateBuffering == self.state) {
        return;
    }
    
    if (!self.fromLocalFile) {
        self.task.priority = CDVideoDownloadTaskPriorityImmediate;
        
        [[CDPlayer dispatcher] tryToStartTask:self.task];
    }
    
    [self.player play];
    [self startDisplayLink];
    
    if (CDVideoDownloadStateError == self.task.state) {
        self.error = self.task.error;
        self.state = CDPlayerStateError;
    } else if ([self couldPlay]) {
        self.state = CDPlayerStatePlaying;
    } else {
        self.state = CDPlayerStateBuffering;
    }
}

- (void)play:(void(^)(void))callback {
    if (CDPlayerStatePreparing == self.state) {
        // setup player even though the asset hasnt load the key
        [self setupPlayer];
        [self _play];
        if (callback) {
            callback();
        }
    } else {
        [self _play];
        if (callback) {
            callback();
        }
    }
}

- (void)play {
    [self play:nil];
    
}

- (void)pause {
    [self.player pause];
    self.state = CDPlayerStatePause;
    
}

- (void)stop {
    [self.player pause];
    [self.player seekToTime:kCMTimeZero];
    self.state = CDPlayerStateStop;
    
}

- (void)destroy {
    [self stopDisplayLink];
}

- (BOOL)couldPlay {
//    return AVPlayerItemStatusReadyToPlay == self.playerItem.status;
    return self.playerItem.isPlaybackLikelyToKeepUp;
}

- (void)continueToBuffer {
    
    self.task.priority = CDVideoDownloadTaskPriorityImmediate;
    [[CDPlayer dispatcher] tryToStartTask:self.task];
    
    [self.player play];
    
    if (CDVideoDownloadStateError == self.task.state) {
        self.error = self.task.error;
        self.state = CDPlayerStateError;
    } else if ([self couldPlay]) {
        self.state = CDPlayerStatePlaying;
    } else {
        self.state = CDPlayerStateBuffering;
    }
}

- (void)_seek {
    double position = self.shouldSeekToPosition;
    
    CGFloat seekTime;
    if (self.fromLocalFile) {
        seekTime = CMTimeGetSeconds(self.asset.duration) * position;
    } else {
        seekTime = [self.task.infoProvider duration] * position;
    }
    
    [self.playerItem seekToTime:CMTimeMakeWithSeconds(seekTime, self.playerItem.currentTime.timescale) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CDPlayerDidSeekToPositionNotif object:nil];
    self.shouldSeekToPosition = 0;
}

- (BOOL)seekToPosition:(double)position {
    if (position < 0) {
        position = 0;
    } else if (position > 1) {
        position = 1;
    }
    
    if (self.fromLocalFile) {
        self.shouldSeekToPosition = position;
        [self _seek];
        
        return YES;
    } else {
        __weak CDPlayer *wself = self;
        
        // 寻找目标位置的数据是否已经下载完，没有的话需要将task.offset定位到这个地方，从这里开始下载
        
        long long bytesOffset = self.task.totalBytes * position;
        __block BOOL found = NO;
        [self.task.loadedVideoBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *videoBlock, NSUInteger idx, BOOL *stop) {
            if ([videoBlock containsPosition:bytesOffset]) {
                found = YES;
                
                if (videoBlock.offset + videoBlock.length < wself.task.totalBytes) {
                    [wself.task pushOffset:videoBlock.offset + videoBlock.length - 1];
                    
                    if (CDVideoDownloadStateLoading != wself.task.state) {
                        [wself.task load];
                    }
                    
                }
                
                *stop = YES;
                
            }
        }];
        
        self.shouldSeekToPosition = position;
        if (found) {
            [self _seek];
            return YES;
        } else {
            
            if (CDVideoDownloadStateLoading != self.task.state) {
                
                if (0 == self.requests.count) {
                    //                [self _seek];
                    long long targetPosition = self.task.totalBytes * position;
                    targetPosition = MAX(targetPosition - [CDVideoDownloadTask VideoBlockSize], 0);
                    [self.task pushOffset:targetPosition];
                    
                    self.state = CDPlayerStateBuffering;
                    [self.task load];
                    
                    return NO;
                    
                } else {
                    long long smallestOffset = 0;
                    for (AVAssetResourceLoadingRequest *loadingRequest in self.requests) {
                        long long startOffset = loadingRequest.dataRequest.requestedOffset;
                        if (loadingRequest.dataRequest.currentOffset != 0) {
                            startOffset = loadingRequest.dataRequest.currentOffset;
                        }
                        
                        if (0 == smallestOffset) {
                            smallestOffset = startOffset;
                        } else {
                            smallestOffset = MIN(smallestOffset, startOffset);
                        }
                    }
                    
                    if (0 != smallestOffset) {
                        long long shouldPushTo = MAX(smallestOffset - [CDVideoDownloadTask VideoBlockSize], 0);
                        [self.task pushOffset:shouldPushTo];
                    }
                    
                    self.state = CDPlayerStateBuffering;
                    
                    return NO;
                }
            } else {
                self.state = CDPlayerStateBuffering;
                
                return NO;
            }
            
            
        }
    }
    
}

- (void)moviePlayDidStalled:(NSNotification *)notif {
    NSLog(@"moviePlayDidStalled");
//    if (notif.object == self.playerItem) {
//        if (CDPlayerStatePlaying == self.state) {
//            self.state = CDPlayerStateBuffering;
//        }
//    }
}

- (void)moviePlayDidEnd:(NSNotification *)notif {
    if (self.loop) {
        
        if (!self.fromLocalFile) {
            self.task.priority = CDVideoDownloadTaskPriorityImmediate;
            [self.task pushOffset:0];
            [[CDPlayer dispatcher] tryToStartTask:self.task];
        }
        
        
        [self.playerItem seekToTime:kCMTimeZero];
        [self.player play];
        
        
    } else {
        [self.playerItem seekToTime:kCMTimeZero];
        self.state = CDPlayerStateStop;
        
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:CDPlayerItemDidPlayToEndTimeNotif object:self.provider];
}

- (void)handleTaskStateDidChanged:(NSNotification *)notif {
    if (self.task == notif.userInfo[CDVideoDownloadTaskNotifTaskKey]) {
        
        if (CDVideoDownloadStateError == self.task.state && CDPlayerStateBuffering == self.state) {
            // 重试重连之后失败，这里该提示用户错误了
            self.error = self.task.error;
            self.state = CDPlayerStateError;
            
        } else if (CDVideoDownloadStateLoaded == self.task.state) {
            [self checkoutUnsatisfiedRequests];
        } else if (CDVideoDownloadStateFinished == self.task.state) {
            [self stopDisplayLink];
        }
    }
}

- (void)handleTaskDidHasNewBlock:(NSNotification *)notif {
//    NSLog(@"hhhhhhhh  %f", self.playerItem.preferredForwardBufferDuration);
    CDVideoDownloadTask *task = notif.userInfo[CDVideoDownloadTaskNotifTaskKey];
    if (task == self.task) {
        [self checkoutUnsatisfiedRequests];
        if (CDPlayerStateStop == self.state || CDPlayerStatePause == self.state) {
            
            return;
        }
        
        if (0 != self.shouldSeekToPosition) {
            [self _seek];
        } else {
            if (CDPlayerStateBuffering == self.state) {
                
                if (self.playerItem.isPlaybackLikelyToKeepUp) {
                    [self.player play];
                    self.state = CDPlayerStatePlaying;
                } else if (AVPlayerItemStatusFailed == self.playerItem.status) {
                    [self.player play]; // 播放item初始化失败，这里给个机会恢复
                }
                
            }
        }
    }
}

- (void)checkoutUnsatisfiedRequests {
    NSMutableArray *completedRequests = [NSMutableArray array];
    __block AVAssetResourceLoadingRequest *firstUnsatisfiedRequest = nil;
    __block BOOL fed = NO;
    [self.requests enumerateObjectsUsingBlock:^(AVAssetResourceLoadingRequest *loadingRequest, NSUInteger idx, BOOL *stop) {
        fed = [self tryToFeedRequest:loadingRequest];
        if (fed) {
            [completedRequests addObject:loadingRequest];
        }
        if (!firstUnsatisfiedRequest) {
            firstUnsatisfiedRequest = loadingRequest;
        } else {
            if (firstUnsatisfiedRequest.dataRequest.currentOffset > loadingRequest.dataRequest.currentOffset) {
                firstUnsatisfiedRequest = loadingRequest;
            }
        }
    }];
    NSLog(@"ffffffffirsssssssss  %@", firstUnsatisfiedRequest);
    if (firstUnsatisfiedRequest) {
        long long smallestOffset = MAX(firstUnsatisfiedRequest.dataRequest.currentOffset, 0);
        [self.task pushOffset:smallestOffset];
        NSLog(@"push offset %lld", smallestOffset);
//        NSLog(@"uuuuuuuuuuuuu  %d", self.task.state);
        
        if (CDVideoDownloadStateLoaded == self.task.state) {
            self.task.priority = CDVideoDownloadTaskPriorityImmediate;
            [[CDPlayer dispatcher] tryToStartTask:self.task];
        }
    }
    
    [self.requests removeObjectsInArray:completedRequests];
}

- (BOOL)tryToFeedRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    if (loadingRequest.contentInformationRequest) {
        CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(@"video/mp4"), NULL);
        loadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
        loadingRequest.contentInformationRequest.contentType = CFBridgingRelease(contentType);
        loadingRequest.contentInformationRequest.contentLength = self.task.totalBytes;
        
//        NSLog(@"total bytes %lld", self.task.totalBytes);

    }
    
    __block BOOL canFinishing = NO;
    
    
    // 关于data request:
    // requestedOffset是指这个请求的起始位置
    // currentOffset是指这个请求当前需要的数据的起始位置，这个位置是相对于整段数据，而不是相对于requestedOffset
    // requestedLength是指这个请求需要的数据的长度
    long long startOffset = loadingRequest.dataRequest.requestedOffset;
    if (loadingRequest.dataRequest.currentOffset != 0) {
        startOffset = loadingRequest.dataRequest.currentOffset;
    }
    
    __weak CDPlayer *wself = self;
    [self.task.loadedVideoBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *videoBlock, NSUInteger idx, BOOL *stop) {
        
        if (startOffset >= videoBlock.offset && startOffset < videoBlock.offset + videoBlock.length) {
            
            long long readingDataLength;
            if (loadingRequest.dataRequest.requestedLength + loadingRequest.dataRequest.requestedOffset - startOffset <= videoBlock.offset + videoBlock.length - startOffset) {
                readingDataLength = loadingRequest.dataRequest.requestedLength + loadingRequest.dataRequest.requestedOffset - startOffset;
                canFinishing = YES;
            } else {
                readingDataLength = videoBlock.offset + videoBlock.length - startOffset;
            }
            
            [wself.fileHandle seekToFileOffset:startOffset];
            NSData *requestedData = [wself.fileHandle readDataOfLength:readingDataLength];
            NSData *fuckthat = [NSData dataWithContentsOfFile:[NSString toAbsolute:self.task.infoProvider.localURLPath]];
            
            NSLog(@"-------------------");
            NSLog(@"data request %@", loadingRequest.dataRequest);
            NSLog(@"reading length %lld", readingDataLength);
            NSLog(@"actual reading length %lld", requestedData.length);
            NSLog(@"the whole file data length %lld", fuckthat.length);
            NSLog(@"video block offset %lld, length %lld", videoBlock.offset, videoBlock.length);
            [loadingRequest.dataRequest respondWithData:requestedData];
            
            if (canFinishing) {
                NSLog(@"let s finish this ");
                [loadingRequest finishLoading];
            }
        }
    }];
    
    return canFinishing;
}



#pragma load
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    
    BOOL fed = [self tryToFeedRequest:loadingRequest];
    
    if (!fed) {
        [self.requests addObject:loadingRequest];
        
        if (CDVideoDownloadStateError == self.task.state || CDVideoDownloadStateLoaded == self.task.state) {
            [self checkoutUnsatisfiedRequests];
        }
    }
    
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    NSLog(@"ccccccccccccccc  %@", loadingRequest);
    [self.requests removeObject:loadingRequest];
    
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForRenewalOfRequestedResource:(AVAssetResourceRenewalRequest *)renewalRequest {
    NSLog(@"nnnnnnnnnnnnnn  %@", renewalRequest);
    return YES;
}

@end
