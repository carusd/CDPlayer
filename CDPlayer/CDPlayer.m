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
#import "CDVideoBlock.h"

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

@end

@implementation CDPlayer

+ (NSString *)dispatcherTag {
    return @"player";
}

+ (id<CDVideoDownloadTaskDispatcher>)dispatcher {
    return [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:[CDPlayer dispatcherTag] class:nil];
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
            self.player.automaticallyWaitsToMinimizeStalling = NO;
        }
        
        self.state = CDPlayerStateStandby;
    }
    
}

- (void)setupWithInfoProvider:(id<CDVideoInfoProvider>)infoProvider {
    self.state = CDPlayerStatePreparing;
    
    self.provider = infoProvider;
    
    NSString *prefix = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *localURLPath = [NSString stringWithFormat:@"%@/%@", prefix, infoProvider.localURLPath];
    
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
        

        
        NSURLComponents *videoURLComponents = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:self.task.videoURLPath] resolvingAgainstBaseURL:NO];
        videoURLComponents.scheme = @"streaming";
        self.asset = [AVURLAsset assetWithURL:videoURLComponents.URL];
        [self.asset.resourceLoader setDelegate:self queue:dispatch_get_main_queue()];

        
        NSError *e = nil;
        self.fileHandle = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:localURLPath] error:&e];
        
        [self setupPlayer];
    }

    
}




- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    

    if ([keyPath isEqualToString:@"status"]) {
        switch (self.playerItem.status) {
            case AVPlayerItemStatusReadyToPlay:
                NSLog(@"ccccccccccccccc  %d, jjjjjjj  %@", self.state, self.task.videoURLPath);
                
                if (CDPlayerStateBuffering == self.state) {
                    
                    [self.player play];
                    if (self.playerItem.playbackLikelyToKeepUp) {
                        self.state = CDPlayerStatePlaying;
                    }
                } else if (CDPlayerStatePause == self.state || CDPlayerStateStop == self.state) {
                    [self.player pause];
                }
                break;
            case AVPlayerItemStatusFailed:
                NSLog(@"lllllllllllll  %@", self.playerItem.error);
                self.error = self.playerItem.error;
                self.state = CDPlayerStateError;
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
        if (self.task.state == CDVideoDownloadStateLoadError) {
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
    
    if (CDVideoDownloadStateLoadError == self.task.state) {
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

- (BOOL)couldPlay {
    return AVPlayerItemStatusReadyToPlay == self.playerItem.status;
//    return self.playerItem.isPlaybackLikelyToKeepUp;
}

- (void)continueToBuffer {
    
    self.task.priority = CDVideoDownloadTaskPriorityImmediate;
    [[CDPlayer dispatcher] tryToStartTask:self.task];
    
    [self.player play];
    
    if (CDVideoDownloadStateLoadError == self.task.state) {
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
    if (notif.object == self.playerItem) {
        if (CDPlayerStatePlaying == self.state) {
            self.state = CDPlayerStateBuffering;
        }
    }
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
        
        if (CDVideoDownloadStateLoadError == self.task.state && CDPlayerStateBuffering == self.state) {
            // 重试重连之后失败，这里该提示用户错误了
            self.error = self.task.error;
            self.state = CDPlayerStateError;
            
        } else if (CDVideoDownloadStateLoaded == self.task.state) {
            [self checkoutUnsatisfiedRequests];
        }
    }
}

- (void)handleTaskDidHasNewBlock:(NSNotification *)notif {
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
                [self.player play];
                if (self.playerItem.isPlaybackLikelyToKeepUp) {
                    self.state = CDPlayerStatePlaying;
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
        if (!fed && !firstUnsatisfiedRequest) {
            firstUnsatisfiedRequest = loadingRequest;
        }
    }];
    
    if (firstUnsatisfiedRequest) {
        long long smallestOffset = MAX(firstUnsatisfiedRequest.dataRequest.currentOffset - [CDVideoDownloadTask VideoBlockSize], 0);
        [self.task pushOffset:smallestOffset];
//        NSLog(@"push offset %lld", smallestOffset);
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
    
    __block BOOL found = NO;
    
    long long startOffset = loadingRequest.dataRequest.requestedOffset;
    if (loadingRequest.dataRequest.currentOffset != 0) {
        startOffset = loadingRequest.dataRequest.currentOffset;
    }
    
    
//    NSLog(@"hhhhhhhhhh  %@", loadingRequest.dataRequest);
    
    __weak CDPlayer *wself = self;
    [self.task.loadedVideoBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *videoBlock, NSUInteger idx, BOOL *stop) {
        long long readingDataLength;
//        if ([UIDevice currentDevice].systemVersion.floatValue >= 9 && loadingRequest.dataRequest.requestsAllDataToEndOfResource) {
            readingDataLength = MIN(loadingRequest.dataRequest.requestedLength, [CDVideoDownloadTask VideoBlockSize]);
//        } else {
//            readingDataLength = loadingRequest.dataRequest.requestedLength;
//        }
        
        
        CDVideoBlock *requestedBlock = [[CDVideoBlock alloc] initWithOffset:startOffset length:readingDataLength];
        if ([videoBlock containsBlock:requestedBlock]) {
            
            [wself.fileHandle seekToFileOffset:startOffset];
            NSData *requestedData = [wself.fileHandle readDataOfLength:readingDataLength];
            
            [loadingRequest.dataRequest respondWithData:requestedData];
            
            
            [loadingRequest finishLoading];
            found = YES;
            
            *stop = YES;
        }
        
    }];
    
    
    
    return found;
}



#pragma load
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    
//    NSLog(@"loading request %@", loadingRequest);
    
    BOOL fed = [self tryToFeedRequest:loadingRequest];
    
    if (!fed) {
        [self.requests addObject:loadingRequest];
        
        if (CDVideoDownloadStateLoadError == self.task.state || CDVideoDownloadStateLoaded == self.task.state) {
            [self checkoutUnsatisfiedRequests];
        }
    }
    
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    
    [self.requests removeObject:loadingRequest];
    
}


@end
