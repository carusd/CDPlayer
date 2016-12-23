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

@property (nonatomic) BOOL fromLocalFile;

@property (nonatomic, strong) CDVideoDownloadTask *task;

@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, strong) id<CDVideoDownloadTaskDispatcher> dispatcher;

@property (nonatomic, strong) NSMutableArray<AVAssetResourceLoadingRequest *> *requests;

@end

@implementation CDPlayer

- (void)dealloc {
    [self.fileHandle closeFile];
    [self.asset.resourceLoader setDelegate:nil queue:dispatch_get_main_queue()];
    
}

- (id)initWithInfo:(id<CDVideoInfoProvider>)infoProvider {
    self = [super init];
    if (self) {
        self.dispatcher = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:@"player" class:nil];
        self.task = [self.dispatcher makeTaskWithInfo:infoProvider];
        
        
        if (self.task.completelyLoaded) {
            self.asset = [AVURLAsset assetWithURL:self.task.localURL];
            self.fromLocalFile = YES;
        } else {
            NSURLComponents *videoURLComponents = [[NSURLComponents alloc] initWithURL:self.task.videoURL resolvingAgainstBaseURL:NO];
            videoURLComponents.scheme = @"streaming";
            self.asset = [AVURLAsset assetWithURL:videoURLComponents.URL];
            [self.asset.resourceLoader setDelegate:self queue:dispatch_get_main_queue()];
            
            self.fileHandle = [NSFileHandle fileHandleForReadingFromURL:self.task.localURL error:nil];
            
            self.fromLocalFile = NO;
        }
        
        self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        
        self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
        self.player.automaticallyWaitsToMinimizeStalling = NO;
        
        
        self.requests = [NSMutableArray array];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskDidHasNewBlock:) name:CDVideoDownloadTaskDidHasNewBlockNotif object:nil];
        
        [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
        [self.playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
        [self.playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
        [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemPlaybackStalled:) name:AVPlayerItemPlaybackStalledNotification object:self.playerItem];
    }
    
    return self;
}

- (void)playerItemPlaybackStalled:(NSNotification *)notif {
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    
    if ([keyPath isEqualToString:@"status"]) {
        switch (self.playerItem.status) {
            case AVPlayerItemStatusReadyToPlay:
                [self.player play];
                break;
            case AVPlayerItemStatusFailed:
            case AVPlayerItemStatusUnknown:
            default:
                break;
        }
    } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
        [self.player play];
    } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
        [self.player pause];
    }
}

- (void)handleTaskDidHasNewBlock:(NSNotification *)notif {
    CDVideoDownloadTask *task = notif.userInfo[CDVideoDownloadTaskNotifTaskKey];
    if (task == self.task) {
        NSMutableArray *completedRequests = [NSMutableArray array];
        for (AVAssetResourceLoadingRequest *loadingRequest in self.requests) {
            BOOL fed = [self tryToFeedRequest:loadingRequest];
            if (fed) {
                [completedRequests addObject:loadingRequest];
            }
        }
        
        [self.requests removeObjectsInArray:completedRequests];
        
    }
}

#pragma control
- (void)play {
    
    if (!self.fromLocalFile) {
        
        [self.dispatcher tryToStartTask:self.task];
    }
    [self.player play];
    
    
}

- (void)pause {
    [self.player pause];
}

- (void)seekToPosition:(double)position {
    [self.playerItem seekToTime:CMTimeMakeWithSeconds(self.task.duration, 30)];
}

- (void)moviePlayDidEnd:(NSNotification *)notif {
    if (self.loop) {
        [self.playerItem seekToTime:kCMTimeZero];
        [self.player play];
    }
    
    
}

- (BOOL)tryToFeedRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    if (loadingRequest.contentInformationRequest) {
        CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(@"video/mp4"), NULL);
        loadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
        loadingRequest.contentInformationRequest.contentType = CFBridgingRelease(contentType);
        loadingRequest.contentInformationRequest.contentLength = self.task.totalBytes;
    }
    
    __block BOOL found = NO;
    
    __weak CDPlayer *wself = self;
    [self.task.loadedVideoBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *videoBlock, NSUInteger idx, BOOL *stop) {
        
        long long readingDataLength = MIN(loadingRequest.dataRequest.requestedLength, [CDVideoDownloadTask VideoBlockSize]);
        
        long long startOffset = loadingRequest.dataRequest.requestedOffset;
        if (loadingRequest.dataRequest.currentOffset != 0) {
            startOffset = loadingRequest.dataRequest.currentOffset;
        }
        
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
    
    
    
    BOOL fed = [self tryToFeedRequest:loadingRequest];
    
    if (!fed) {
//        if (loadingRequest.dataRequest.requestedOffset > 0) {
//            self.task.offset = loadingRequest.dataRequest.requestedOffset;
//        }
        
        
        [self.requests addObject:loadingRequest];
    }
    
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    
    [self.requests removeObject:loadingRequest];
    
}
@end
