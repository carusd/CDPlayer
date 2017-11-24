//
//  CDPlayer.h
//  CDPlayer
//
//  Created by carusd on 2016/11/29.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "CDDownloadProtocol.h"
#import <AVFoundation/AVFoundation.h>
#import "CDVideoDownloadTask.h"

extern NSString * const CDPlayerDidSeekToPositionNotif;
extern NSString * const CDPlayerItemDidPlayToEndTimeNotif;

@interface CDPlayer : NSObject

- (id)initWithInfo:(id<CDVideoInfoProvider>)infoProvider;


@property (nonatomic, readonly) AVPlayer *player;
@property (nonatomic, readonly) CDPlayerState state;
@property (nonatomic, readonly) NSError *error;
@property (nonatomic) BOOL loop;
@property (nonatomic ,readonly) BOOL fromLocalFile;
@property (nonatomic, readonly) CDVideoDownloadTask *task;
@property (nonatomic, readonly) CGFloat playProgress;
@property (nonatomic, readonly) NSMutableArray<AVAssetResourceLoadingRequest *> *requests;


+ (NSString *)dispatcherTag;
+ (id<CDVideoDownloadTaskDispatcher>)dispatcher;

- (void)play:(void(^)(void))callback;
- (void)play;
- (void)pause;
- (void)stop;
- (void)continueToBuffer; // 因为错误被迫停止，需要重新开始加载的时候，调用这个方法
- (void)destroy; // 如果要销毁CDPlayer，必须先调用这个

- (BOOL)seekToPosition:(double)position;


@end
