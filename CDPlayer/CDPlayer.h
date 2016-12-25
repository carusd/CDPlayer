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


@interface CDPlayer : NSObject

- (id)initWithInfo:(id<CDVideoInfoProvider>)infoProvider;

@property (nonatomic, readonly) AVPlayer *player;
@property (nonatomic, readonly) CDPlayerState state;

@property (nonatomic, readonly) NSError *error;

@property (nonatomic) BOOL loop;
@property (nonatomic ,readonly) BOOL fromLocalFile;

@property (nonatomic) BOOL playOnWhileKeepUp;

@property (nonatomic, readonly) CDVideoDownloadTask *task;

- (void)play;
- (void)pause;

- (void)continueToBuffer; // 因为错误被迫停止，需要重新开始加载的时候，调用这个方法

- (void)seekToPosition:(double)position;

@end
