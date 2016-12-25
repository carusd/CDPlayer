//
//  CDDownloadProtocol.h
//  CDPlayer
//
//  Created by carusd on 2016/11/25.
//  Copyright © 2016年 carusd. All rights reserved.
//

@protocol CDVideoInfoProvider <NSObject>

@property (readonly) NSURL *videoURL;
@property (readonly) NSURL *localURL;
@property (readonly) NSInteger duration; // 单位为秒
@property (readonly, copy) NSString *title;

@optional

@property (readonly) BOOL completelyLoaded;
@property (readonly) int64_t size; // 单位为byte
@property (readonly) int64_t width;
@property (readonly) int64_t height;
@end


@class CDVideoDownloadTask;
@protocol CDVideoDownloadTaskPersistenceManager <NSObject>

@property (nonatomic, readonly) NSURL *cacheDirURL;

- (NSMutableArray<CDVideoDownloadTask *> *)tasksWithTag:(NSString *)tag;
- (void)addTask:(CDVideoDownloadTask *)task;
- (void)removeTask:(CDVideoDownloadTask *)task;


@end

@protocol CDVideoDownloadTaskDispatcher <NSObject>

- (id)initWithTag:(NSString *)tag;
@property (nonatomic, readonly) NSString *tag;

@property (nonatomic, readonly, weak) id<CDVideoDownloadTaskPersistenceManager> persistenceManager;

@property (nonatomic) NSInteger maxConcurrentNum;

- (CDVideoDownloadTask *)makeTaskWithInfo:(id<CDVideoInfoProvider>)provider;

- (void)tryToStartTask:(CDVideoDownloadTask *)task;
- (void)addTask:(CDVideoDownloadTask *)task;
- (void)removeTask:(CDVideoDownloadTask *)task;
- (BOOL)containsTask:(CDVideoDownloadTask *)task;
- (void)clearTasks;
- (void)pauseAllLoadingTasks;
- (BOOL)loading;

- (NSArray<CDVideoDownloadTask *> *)loadingTasks;
- (NSArray<CDVideoDownloadTask *> *)allTasks;
@end

typedef enum : int64_t {
    CDVideoDownloadStateStandby,
    CDVideoDownloadStateWaiting,
    CDVideoDownloadStateLoading,
    CDVideoDownloadStatePause,
    CDVideoDownloadStateLoadError,
    CDVideoDownloadStateLoaded,       // 分段下载时，有时候会跳到后面一段继续下载，这时候下载完时其实是不完整的，这种状态用Finished来表示
    CDVideoDownloadStateFinished     // 不仅仅下载到最后，而且文件是完整下载好的
} CDVideoDownloadState;

typedef enum : NSUInteger {
    CDVideoDownloadTaskPriorityMedium,
    CDVideoDownloadTaskPriorityImmediate, // 该优先级同一时间只允许有一个，如果同时出现了两个，其中一个会被降级
} CDVideoDownloadTaskPriority;

typedef enum : NSUInteger {
    CDPlayerStatePlaying,
    CDPlayerStateError,
    CDPlayerStatePause,
    CDPlayerStateStop,
    CDPlayerStateBuffering
} CDPlayerState;

