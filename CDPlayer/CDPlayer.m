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
        
        self.task = [[CDPlayer dispatcher] makeTaskWithInfo:infoProvider];
        NSString *prefix = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *localURLPath = [NSString stringWithFormat:@"%@/%@", prefix, self.task.localURLPath];
        
        if (infoProvider.completelyLoaded) {
            self.asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:localURLPath]];
            self.fromLocalFile = YES;
        } else {
            NSURLComponents *videoURLComponents = [[NSURLComponents alloc] initWithURL:[NSURL URLWithString:self.task.videoURLPath] resolvingAgainstBaseURL:NO];
            videoURLComponents.scheme = @"streaming";
            self.asset = [AVURLAsset assetWithURL:videoURLComponents.URL];
            [self.asset.resourceLoader setDelegate:self queue:dispatch_get_main_queue()];
            
            NSError *e = nil;
            self.fileHandle = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:localURLPath] error:&e];
//            self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:localURLPath];
            if (e) {
                NSLog(@"eeeeeeeeeee  %@", e);
            }
            
            self.fromLocalFile = NO;
        }
        
        self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        
        self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
//        self.player.automaticallyWaitsToMinimizeStalling = NO;
        
        self.playOnWhileKeepUp = YES;
        
        self.requests = [NSMutableArray array];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskDidHasNewBlock:) name:CDVideoDownloadTaskDidHasNewBlockNotif object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskStateDidChanged:) name:CDVideoDownloadStateDidChangedNotif object:nil];
        
        [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
        [self.playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
        [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemPlaybackStalled:) name:AVPlayerItemPlaybackStalledNotification object:self.playerItem];
    }
    
    return self;
}

+ (NSString *)dispatcherTag {
    return @"player";
}

+ (id<CDVideoDownloadTaskDispatcher>)dispatcher {
    return [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:[CDPlayer dispatcherTag] class:nil];
}

- (void)playerItemPlaybackStalled:(NSNotification *)notif {
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    
    if ([keyPath isEqualToString:@"status"]) {
        switch (self.playerItem.status) {
            case AVPlayerItemStatusReadyToPlay:
                NSLog(@"ffffffffff");
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
//        if (self.task.state == CDVideoDownloadStateLoading) {
//            self.state = CDPlayerStateBuffering;
//        } else if (self.task.state == CDVideoDownloadStateLoadError) {
//            // 下载途中失败之后，播放器还是继续在播放，这个时候不应该就马上显示错误
//            // 而是继续播放，直到playbackBufferEmpty为真，这个时候还是不应该马上
//            // 显示错误。而是尝试重新下载，重新下载还是失败，在handleTaskStateDidChanged
//            // 中处理
//            [self.task load];
//            self.state = CDPlayerStateBuffering;
//        }
        
    }
}

- (void)handleTaskStateDidChanged:(NSNotification *)notif {
    if (self.task == notif.userInfo[CDVideoDownloadTaskNotifTaskKey]) {
        if (CDVideoDownloadStateLoadError == self.task.state && CDPlayerStateBuffering == self.state) {
            // 重试重连之后失败，这里该提示用户错误了
            self.state = CDPlayerStateError;
            self.error = self.task.error;
        }
    }
}

- (void)handleTaskDidHasNewBlock:(NSNotification *)notif {
    CDVideoDownloadTask *task = notif.userInfo[CDVideoDownloadTaskNotifTaskKey];
    if (task == self.task) {
        NSMutableArray *completedRequests = [NSMutableArray array];
        
        for (AVAssetResourceLoadingRequest *loadingRequest in self.requests) {
//            NSLog(@"before %@", loadingRequest);
            BOOL fed = [self tryToFeedRequest:loadingRequest];
            if (fed) {
                [completedRequests addObject:loadingRequest];
            }
        }
        
        [self.requests removeObjectsInArray:completedRequests];
        
        
        if (CDPlayerStateBuffering == self.state) {
            [self.player play];
            if (self.playerItem.isPlaybackLikelyToKeepUp) {
                self.state = CDPlayerStatePlaying;
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
    
    if (!self.playerItem.playbackLikelyToKeepUp && CDVideoDownloadStateLoading == self.task.state) {
        self.state = CDPlayerStateBuffering;
    }
    
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
    
    if (!self.playerItem.playbackLikelyToKeepUp && CDVideoDownloadStateLoading == self.task.state) {
        self.state = CDPlayerStateBuffering;
    }
    
}

- (void)seekToPosition:(double)position {
    CGFloat seekTime = [self.task.infoProvider duration] * position;
    
    [self.playerItem seekToTime:CMTimeMakeWithSeconds(seekTime, self.playerItem.currentTime.timescale)];
    
    NSLog(@"seek to postion %f", position);
    __weak CDPlayer *wself = self;
    // 寻找目标位置的数据是否已经下载完，没有的话需要将task.offset定位到这个地方，从这里开始下载
    long long bytesOffset = self.task.totalBytes * position;
    [self.task.loadedVideoBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *videoBlock, NSUInteger idx, BOOL *stop) {
        if (![videoBlock containsPosition:bytesOffset]) {
            [wself.task pushOffset:MAX(0, bytesOffset - 1000)];// 往前边挪一边，保证最左边的数据完整
            
        }
    }];
}

- (void)seekToTime:(CMTime)time {
    [self.playerItem seekToTime:time];
}

- (void)moviePlayDidEnd:(NSNotification *)notif {
    if (self.loop) {
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
//        loadingRequest.contentInformationRequest.contentLength = 16512030;
    }
    
    __block BOOL found = NO;
    
    __weak CDPlayer *wself = self;
    [self.task.loadedVideoBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *videoBlock, NSUInteger idx, BOOL *stop) {
        
        long long readingDataLength = MIN(loadingRequest.dataRequest.requestedLength, [CDVideoDownloadTask VideoBlockSize]);
//        long long readingDataLength = loadingRequest.dataRequest.requestedLength;
        
        long long startOffset = loadingRequest.dataRequest.requestedOffset;
        if (loadingRequest.dataRequest.currentOffset != 0) {
            startOffset = loadingRequest.dataRequest.currentOffset;
        }
        
        CDVideoBlock *requestedBlock = [[CDVideoBlock alloc] initWithOffset:startOffset length:readingDataLength];
        if ([videoBlock containsBlock:requestedBlock]) {
            
            found = YES;
            
            [wself.fileHandle seekToFileOffset:startOffset];
            NSData *requestedData = [wself.fileHandle readDataOfLength:readingDataLength];
//            NSLog(@"start offset %lld", startOffset);
//            NSLog(@"reading length %lld", readingDataLength);
//            NSLog(@"real length %lld", requestedData.length);
            [loadingRequest.dataRequest respondWithData:requestedData];
            [loadingRequest finishLoading];
            *stop = YES;
        }
        
    }];
    
    return found;
}

#pragma load
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    
    
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
