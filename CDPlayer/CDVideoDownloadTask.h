//
//  CDVideoDownloadTask.h
//  CDPlayer
//
//  Created by carusd on 2016/11/29.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDDownloadProtocol.h"
#import <UIKit/UIKit.h>


extern NSString * const CDVideoDownloadStateDidChangedNotif;
extern NSString * const CDVideoDownloadTaskDidHasNewBlockNotif;

extern NSString * const CDVideoDownloadTaskNotifTaskKey;


typedef void(^HandleDownloadProgress)(CGFloat);
@interface CDVideoDownloadTask : NSObject<CDVideoInfoProvider, NSCoding>



- (id)initWithURL:(NSURL *)videoURL localURL:(NSURL *)localURL taskURL:(NSURL *)taskURL;


@property (nonatomic, readonly) NSURL *taskURL;
@property (readonly) CDVideoDownloadState state;
@property (nonatomic) NSInteger priority;
@property (nonatomic) long long offset;
@property (nonatomic, readonly) int64_t totalBytes;
@property (nonatomic, readonly) NSArray<NSValue *> *loadedVideoBlocks; // 表示已经下载的时间区间
@property (nonatomic, readonly) CGFloat progress;
@property (nonatomic, readonly) NSArray<NSString *> *tags;
@property (nonatomic, readonly) NSError *error;  // 当下载出错时，这里会记录出错原因。否则为nil

@property (nonatomic, copy) HandleDownloadProgress handleDownloadProgress;
@property (nonatomic, copy) NSString *label; // 调试用，默认为视频title


- (void)addTag:(NSString *)tag;
- (void)removeTag:(NSString *)tag;

- (void)load;
- (void)yield;
- (void)pause;

- (void)destroy; // 删除视频文件，但是不会删除task文件，因为task事实上不能脱离manager存在，他应该被manager管理


+ (void)setVideoBlockSize:(long long)size;
@end
