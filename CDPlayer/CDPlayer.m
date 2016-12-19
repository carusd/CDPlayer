//
//  CDPlayer.m
//  CDPlayer
//
//  Created by carusd on 2016/12/2.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDPlayer.h"
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

@property (nonatomic, strong) NSMutableArray<AVAssetResourceLoadingDataRequest *> *requests;

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
        [self.dispatcher addTask:self.task];
        
        
        if (self.task.completelyLoaded) {
            self.asset = [AVURLAsset assetWithURL:self.task.localURL];
            self.fromLocalFile = YES;
        } else {
            self.asset = [AVURLAsset assetWithURL:self.task.videoURL];
            [self.asset.resourceLoader setDelegate:self queue:dispatch_get_main_queue()];
            
            
            self.fileHandle = [NSFileHandle fileHandleForReadingFromURL:self.task.localURL error:nil];
            self.fromLocalFile = NO;
        }
        
        self.playerItem = [AVPlayerItem playerItemWithAsset:self.asset];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        
        self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
        
        self.requests = [NSMutableArray array];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskDidHasNewBlock:) name:CDVideoDownloadTaskDidHasNewBlockNotif object:nil];
    }
    
    return self;
}

- (void)handleTaskDidHasNewBlock:(NSNotification *)notif {
    CDVideoDownloadTask *task = notif.userInfo[CDVideoDownloadTaskNotifTaskKey];
    if (task == self.task) {
        for (AVAssetResourceLoadingRequest *loadingRequest in self.requests) {
            [self tryToFeedRequest:loadingRequest];
        }
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
    __block BOOL found = NO;
    
    __weak CDPlayer *wself = self;
    [self.task.loadedVideoBlocks enumerateObjectsUsingBlock:^(NSValue *blockValue, NSUInteger idx, BOOL *stop) {
        
        CDVideoBlock videoBlock;
        [blockValue getValue:&videoBlock];
        
        CDVideoBlock requestedBlock = {loadingRequest.dataRequest.requestedOffset, loadingRequest.dataRequest.requestedLength};
        
        if (CDVideoBlockContainsBlock(videoBlock, requestedBlock)) {
            found = YES;
            
            [wself.fileHandle seekToFileOffset:loadingRequest.dataRequest.requestedOffset];
            NSData *requestedData = [wself.fileHandle readDataOfLength:loadingRequest.dataRequest.requestedLength];
            
            [loadingRequest.dataRequest respondWithData:requestedData];
            
            *stop = YES;
        }
        
    }];
    
    return YES;
}

#pragma load
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    BOOL fed = [self tryToFeedRequest:loadingRequest];
    
    if (!fed) {
        self.task.offset = loadingRequest.dataRequest.requestedOffset;
        [self.requests addObject:loadingRequest];
    }
    
    return YES;
}


@end
