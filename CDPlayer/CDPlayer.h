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

@property (nonatomic) BOOL loop;
@property (nonatomic ,readonly) BOOL fromLocalFile;

@property (nonatomic, readonly) CDVideoDownloadTask *task;

- (void)play;
- (void)pause;

- (void)seekToPosition:(double)position;

@end
