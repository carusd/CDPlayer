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
#import "CDVideoBlock.h"


extern NSString * const CDVideoDownloadErrorDomain;

typedef enum : NSUInteger {
    CDVideoDownloadTaskErrorCodeLoadError,
    CDVideoDownloadTaskErrorCodePrepareLoadError,
    CDVideoDownloadTaskErrorCodeCreateFileHandleError
} CDVideoDownloadTaskErrorCode;

extern NSString * const CDVideoDownloadStateDidChangedNotif;
extern NSString * const CDVideoDownloadTaskDidHasNewBlockNotif;
extern NSString * const CDVideoDownloadTaskInconsistenceNotif;
extern NSString * const CDVideoDownloadTaskLoadBlockUseTimeNotif;

extern NSString * const CDVideoDownloadTaskNotifTaskKey;
extern NSString * const CDVideoDownloadTaskNotifRequestRangeKey;
extern NSString * const CDVideoDownloadTaskNotifResponseRangeKey;


extern NSString * const CDVideoDownloadBackgroundSessionIdentifier;

typedef void(^HandleDownloadProgress)(CGFloat);
@class CDPlayer;
@interface CDVideoDownloadTask : NSObject<CDVideoInfoProvider, NSCoding>



- (id)initWithVideoInfoProvider:(id<CDVideoInfoProvider>)provider taskURLPath:(NSString *)taskURLPath;


@property (nonatomic, weak) CDPlayer *player;
@property (nonatomic, readonly) NSString *taskURLPath;
@property (readonly) CDVideoDownloadState state;
@property (nonatomic) NSInteger priority;
@property (nonatomic, readonly) long long offset;
@property (nonatomic, readonly) int64_t totalBytes;
@property (nonatomic, readonly) NSArray<CDVideoBlock *> *loadedVideoBlocks; // 表示已经下载的时间区间
@property (nonatomic, readonly) NSArray<CDVideoNormalizedBlock *> *loadedVideoRanges; //同上，但是这是正则化表示，范围是0-1
@property (nonatomic, readonly) CGFloat progress;
@property (nonatomic, readonly) NSString *videoFileMD5;
@property (nonatomic, readonly) NSArray<NSString *> *tags;
@property (nonatomic, readonly) NSError *error;  // 当下载出错时，这里会记录出错原因。否则为nil

@property (nonatomic, copy) HandleDownloadProgress handleDownloadProgress;
@property (nonatomic, copy) NSString *label; // 调试用，默认为视频title

@property (nonatomic) NSTimeInterval createTime;

@property (nonatomic, readonly) id<CDVideoInfoProvider> infoProvider;


@property (nonatomic) NSUInteger frequency; // 下载频率，通过添加下载等待时间来控制宽带占用
@property (nonatomic) NSInteger loadBlockTime; // 当前请求的用时

- (long long)sizeInDisk;

- (void)addTag:(NSString *)tag;
- (void)removeTag:(NSString *)tag;


- (void)save;


- (void)load;
- (void)yield;
- (void)pause;

- (void)destroy; // 删除视频文件和task文件
- (void)pushOffset:(long long)offset;

+ (void)setVideoBlockSize:(long long)size;
+ (long long)VideoBlockSize;


@end
