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

@interface CDPlayer()<AVAssetResourceLoaderDelegate>

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVURLAsset *asset;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic) CDPlayerState state;

@property (nonatomic, strong) NSError *error;

@property (nonatomic) BOOL fromLocalFile;

@property (nonatomic, strong) CDVideoDownloadTask *task;

@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, strong) NSMutableArray<AVAssetResourceLoadingRequest *> *requests;

@property (nonatomic) BOOL shouldPushOffset;

@property (nonatomic) double shouldSeekToPosition;


@end

@implementation CDPlayer

- (void)dealloc {
    [self.task pause];
    
    [self.fileHandle closeFile];
    [self.asset.resourceLoader setDelegate:nil queue:dispatch_get_main_queue()];
    
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.playerItem removeObserver:self forKeyPath:@"status"];
    [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
}

- (id)initWithInfo:(id<CDVideoInfoProvider>)infoProvider {
    self = [super init];
    if (self) {
        [self setupWithInfoProvider:infoProvider];
        
        self.state = CDPlayerStateStop;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskDidHasNewBlock:) name:CDVideoDownloadTaskDidHasNewBlockNotif object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskStateDidChanged:) name:CDVideoDownloadStateDidChangedNotif object:nil];
    }
    
    return self;
}

- (void)replaceCurrentVideoWithVideo:(id<CDVideoInfoProvider>)infoProvider {
    [self.playerItem removeObserver:self forKeyPath:@"status"];
    [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    
    
    [self setupWithInfoProvider:infoProvider];
}

- (void)setupWithInfoProvider:(id<CDVideoInfoProvider>)infoProvider {
    NSString *prefix = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *localURLPath = [NSString stringWithFormat:@"%@/%@", prefix, infoProvider.localURLPath];
    
    if (infoProvider.completelyLoaded) {
        NSLog(@"completly loaded?");
        self.asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:localURLPath]];
        self.fromLocalFile = YES;
    } else {
        NSLog(@"should load!");
        
        self.task = [[CDPlayer dispatcher] makeTaskWithInfo:infoProvider];
        [self.task pushOffset:0]; // 有些任务可能是下载到一半的，这里重置下载位置，确保开始的播放
        
        
        NSURLComponents *videoURLComponents = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:self.task.videoURLPath] resolvingAgainstBaseURL:NO];
        videoURLComponents.scheme = @"streaming";
        self.asset = [AVURLAsset assetWithURL:videoURLComponents.URL];
        [self.asset.resourceLoader setDelegate:self queue:dispatch_get_main_queue()];
        
        NSError *e = nil;
        self.fileHandle = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:localURLPath] error:&e];
        
        
        self.fromLocalFile = NO;
    }
    
    if (self.playerItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:self.asset];
        [self.player replaceCurrentItemWithPlayerItem:playerItem];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        self.playerItem = playerItem;
        
    } else {
        self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        
        self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 10) {
            self.player.automaticallyWaitsToMinimizeStalling = NO;
        }
    }
    
    
    self.playOnWhileKeepUp = YES;
    
    self.requests = [NSMutableArray array];
    
    [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [self.playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    
    
}

+ (NSString *)dispatcherTag {
    return @"player";
}

+ (id<CDVideoDownloadTaskDispatcher>)dispatcher {
    return [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:[CDPlayer dispatcherTag] class:nil];
}



- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    
    if ([keyPath isEqualToString:@"status"]) {
        switch (self.playerItem.status) {
            case AVPlayerItemStatusReadyToPlay:
                
                break;
            case AVPlayerItemStatusFailed:
            case AVPlayerItemStatusUnknown:
            default:
                break;
        }
    } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
        if (!self.playerItem.playbackLikelyToKeepUp) {
            if (CDPlayerStatePlaying == self.state && CDVideoDownloadStateLoading == self.task.state) {
                self.state = CDPlayerStateBuffering;
            }
        }
    } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
        if (self.task.state == CDVideoDownloadStateLoadError) {
            
            self.state = CDPlayerStateError;
//            // 下载途中失败之后，播放器还是继续在播放，这个时候不应该就马上显示错误
//            // 而是继续播放，直到playbackBufferEmpty为真，这个时候还是不应该马上
//            // 显示错误。而是尝试重新下载，重新下载还是失败，在handleTaskStateDidChanged
//            // 中处理
//            [self.task load];
//            self.state = CDPlayerStateBuffering;
        }
        
    } else if ([keyPath isEqualToString:@"timebase"]) {
//        NSLog(@"gggggggggggg");
    }
//    NSLog(@"kkkkkkkkkkkkk  %@", keyPath);
}

- (void)handleTaskStateDidChanged:(NSNotification *)notif {
    if (self.task == notif.userInfo[CDVideoDownloadTaskNotifTaskKey]) {
        
        if (CDVideoDownloadStateLoadError == self.task.state && CDPlayerStateBuffering == self.state) {
            // 重试重连之后失败，这里该提示用户错误了
            self.error = self.task.error;
            self.state = CDPlayerStateError;
            
        }
    }
}

- (void)handleTaskDidHasNewBlock:(NSNotification *)notif {
    if (CDPlayerStateStop == self.state || CDPlayerStatePause == self.state) {
        
        return;
    }
    CDVideoDownloadTask *task = notif.userInfo[CDVideoDownloadTaskNotifTaskKey];
    if (task == self.task) {
        NSMutableArray *completedRequests = [NSMutableArray array];
        
        
        long long smallestOffset = 0;
        for (AVAssetResourceLoadingRequest *loadingRequest in self.requests) {
            
            BOOL fed = [self tryToFeedRequest:loadingRequest];
            if (fed) {
                [completedRequests addObject:loadingRequest];
            } else {
                
                long long startOffset = loadingRequest.dataRequest.requestedOffset;
//                NSLog(@"old start offset %lld", startOffset);
                if (loadingRequest.dataRequest.currentOffset != 0) {
                    startOffset = loadingRequest.dataRequest.currentOffset;
//                    NSLog(@"new start offset %lld", startOffset);
                }
                
                if (0 == smallestOffset) {
                    smallestOffset = startOffset;
                } else {
                    smallestOffset = MIN(smallestOffset, startOffset);
//                    NSLog(@"smallest offset %lld", smallestOffset);
                }
            }
        }
        
        
        
        if (0 != smallestOffset) {
            
            long long shouldPushTo = MAX(smallestOffset - [CDVideoDownloadTask VideoBlockSize], 0);
//            NSLog(@"should push to %lld", shouldPushTo);
            [self.task pushOffset:shouldPushTo];
        }
        
        
        [self.requests removeObjectsInArray:completedRequests];
        
        if (0 == self.requests.count && 0 != self.shouldSeekToPosition) {
            [self _seek];
        } else {
            if (CDPlayerStateBuffering == self.state) {
                [self.player play];
                self.state = CDPlayerStatePlaying;
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    float realRate = CMTimebaseGetRate(self.player.currentItem.timebase);
                    if (realRate <= 0) {
                        self.state = CDPlayerStateBuffering;
                    }
                });
            }
        }
    }
}

#pragma control
- (void)play {
    
    if (!self.fromLocalFile) {
        self.task.priority = CDVideoDownloadTaskPriorityImmediate;
        
        [[CDPlayer dispatcher] tryToStartTask:self.task];
    }
    
    
    [self.player play];
    self.state = CDPlayerStatePlaying;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        float rate = self.player.rate;
//        NSLog(@"ffffffffff  %f", rate);
        if (rate <= 0 && CDVideoDownloadStateLoading == self.task.state) {
            self.state = CDPlayerStateBuffering;
        }
        
        if (CDVideoDownloadStateLoadError == self.task.state) {
            self.error = self.task.error;
            self.state = CDPlayerStateError;
            
        }
    });
    
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        float realRate = CMTimebaseGetRate(self.player.currentItem.timebase);
//        if (realRate > 0) {
//            self.state = CDPlayerStatePlaying;
//        } else {
//            if (CDVideoDownloadStateLoading == self.task.state) {
//                self.state = CDPlayerStateBuffering;
//            }
//        }
//    });
}

- (void)pause {
    [self.player pause];
    self.state = CDPlayerStatePause;
    
}

- (void)continueToBuffer {
    
    self.task.priority = CDVideoDownloadTaskPriorityImmediate;
    [[CDPlayer dispatcher] tryToStartTask:self.task];
    
    [self.player play];
    self.state = CDPlayerStatePlaying;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        float rate = self.player.rate;
        
        if (rate <= 0 && CDVideoDownloadStateLoading == self.task.state) {
            self.state = CDPlayerStateBuffering;
        }
        
        if (CDVideoDownloadStateLoadError == self.task.state) {
            self.error = self.task.error;
            self.state = CDPlayerStateError;
        }
    });
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
        self.state = CDPlayerStateStop;
    }
    
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
    
    __weak CDPlayer *wself = self;
    [self.task.loadedVideoBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *videoBlock, NSUInteger idx, BOOL *stop) {
        
        long long readingDataLength = MIN(loadingRequest.dataRequest.requestedLength, [CDVideoDownloadTask VideoBlockSize]);
        
        CDVideoBlock *requestedBlock = [[CDVideoBlock alloc] initWithOffset:startOffset length:readingDataLength];
        if ([videoBlock containsBlock:requestedBlock]) {
            
            found = YES;
            
            [wself.fileHandle seekToFileOffset:startOffset];
            NSData *requestedData = [wself.fileHandle readDataOfLength:readingDataLength];
            
            [loadingRequest.dataRequest respondWithData:requestedData];
            [loadingRequest finishLoading];
            *stop = YES;
        }
        
    }];
    
    
    
    return found;
}

#pragma load
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSLog(@"loading request %@", loadingRequest);
    BOOL fed = [self tryToFeedRequest:loadingRequest];
    
    if (!fed) {
        [self.requests addObject:loadingRequest];
    }
    
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    
    [self.requests removeObject:loadingRequest];
    
}
@end
