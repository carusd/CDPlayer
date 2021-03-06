//
//  CDDownloadProtocol.h
//  CDPlayer
//
//  Created by carusd on 2016/11/25.
//  Copyright © 2016年 carusd. All rights reserved.
//

@protocol CDVideoInfoProvider <NSObject, NSCoding>

@property (readonly) NSString *videoURLPath;
@property (readonly) NSString *localURLPath; // 相对Caches的路径，比如说完整路径是/Library/Caches/tmp.mp4, 则这个字段的值应该是tmp.mp4
@property (readonly) NSString *completeLocalPath;

@optional

@property (readonly) int64_t duration; // 单位为秒
@property (readonly) BOOL completelyLoaded;
@property (readonly, copy) NSString *title;
@property (readonly) int64_t size; // 单位为byte
@property (readonly) int64_t width;
@property (readonly) int64_t height;
@property (readonly, copy) NSString *md5;
@end


@class CDVideoDownloadTask;
@protocol CDVideoDownloadTaskPersistenceManager <NSObject>


@property (nonatomic, readonly) NSString *taskDirURLAbsolutePath;
@property (nonatomic, readonly) NSString *videoDirURLAbsolutePath;

- (NSMutableArray<CDVideoDownloadTask *> *)tasksWithTag:(NSString *)tag;
- (void)addTask:(CDVideoDownloadTask *)task;
- (void)removeTask:(CDVideoDownloadTask *)task;
- (void)removeTasksInArray:(NSArray *)tasks;

@end

@protocol CDVideoDownloadTaskDispatcher <NSObject>

- (id)initWithTag:(NSString *)tag;
@property (nonatomic, readonly) NSString *tag;

@property (nonatomic, readonly, weak) id<CDVideoDownloadTaskPersistenceManager> persistenceManager;

@property (nonatomic) NSInteger maxConcurrentNum;
@property (nonatomic) NSInteger capacity;

- (CDVideoDownloadTask *)taskWithInfo:(id<CDVideoInfoProvider>)provider;
- (CDVideoDownloadTask *)makeTaskWithInfo:(id<CDVideoInfoProvider>)provider;

- (void)tryToStartTask:(CDVideoDownloadTask *)task;
- (void)addTask:(CDVideoDownloadTask *)task;
- (void)removeTask:(CDVideoDownloadTask *)task;
- (void)removeTaskWithInfoProvider:(id<CDVideoInfoProvider>)provider;
- (BOOL)containsTask:(CDVideoDownloadTask *)task;
- (long long)sizeInDisk; // 单位为byte
- (void)clearTasks:(void(^)(void))completion;
- (void)launchLoading;
- (void)pauseAllLoadingTasks;
- (BOOL)loading;

- (NSArray<CDVideoDownloadTask *> *)finishedTasks;
- (NSArray<CDVideoDownloadTask *> *)loadingTasks;
- (NSArray<CDVideoDownloadTask *> *)allTasks;

@property (nonatomic, strong) dispatch_group_t clearTasksGroup;
@end

typedef enum : int64_t {
    CDVideoDownloadStateStandby,
    CDVideoDownloadStateWaiting,
    CDVideoDownloadStateLoading,
    CDVideoDownloadStatePause,
    CDVideoDownloadStateLoadError,    // deprecated，用CDVideoDownloadStateError，并从error变量获取具体错误原因
    CDVideoDownloadStateLoaded,       // 分段下载时，有时候会跳到后面一段继续下载，这时候下载完时其实是不完整的，这种状态用Finished来表示
    CDVideoDownloadStateFinished,     // 不仅仅下载到最后，而且文件是完整下载好的
    CDVideoDownloadStateInit,         // 刚刚初始化
    CDVideoDownloadStatePreparing,
    CDVideoDownloadStateError
} CDVideoDownloadState;

typedef enum : NSUInteger {
    CDVideoDownloadTaskPriorityMedium,
    CDVideoDownloadTaskPriorityImmediate, // 该优先级同一时间只允许有一个，如果同时出现了两个，其中一个会被降级
} CDVideoDownloadTaskPriority;

typedef enum : NSUInteger {
    CDPlayerStatePreparing,
    CDPlayerStateStandby,
    CDPlayerStatePlaying,
    CDPlayerStateError,
    CDPlayerStatePause,
    CDPlayerStateStop,
    CDPlayerStateBuffering
} CDPlayerState;
