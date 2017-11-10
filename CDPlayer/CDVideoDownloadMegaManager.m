//
//  CDVideoDownloadMegaManager.m
//  CDPlayer
//
//  Created by carusd on 2016/12/7.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "CDVideoDownloadMegaManager.h"
#import "CDVideoDownloadManager.h"
#import "CDVideoDownloadTask.h"
#import "NSString+CDFilePath.h"



@interface CDVideoDownloadMegaManager ()

@property (nonatomic, strong) NSMutableDictionary *dispatchers;
@property (nonatomic, strong) NSMutableArray *allTasks; // lazy load

@end

@implementation CDVideoDownloadMegaManager



+ (instancetype)sharedInstance {
    static CDVideoDownloadMegaManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[CDVideoDownloadMegaManager alloc] init];
    });
    
    return manager;
}

- (id)init {
    self = [super init];
    if (self) {
        self.dispatchers = [NSMutableDictionary dictionary];
        
        self.taskDirName = @"com.carusd.videotask";
        self.videoDirName = @"com.carusd.video";
        
    }
    return self;
}

- (id<CDVideoDownloadTaskDispatcher>)dispatcherWithTag:(NSString *)tag class:(Class)clazz {
    id<CDVideoDownloadTaskDispatcher> dispatcher = self.dispatchers[tag];
    if (dispatcher) {
        return dispatcher;
    }
    
    if (clazz == nil) {
        dispatcher = [[CDVideoDownloadManager alloc] initWithTag:tag];
        self.dispatchers[tag] = dispatcher;
        
        return dispatcher;
        
    }
    
    if (![clazz conformsToProtocol:@protocol(CDVideoDownloadTaskDispatcher)]) {
        @throw @"调度下载任务类必须实现CDVideoDownloadTaskDispatcher协议";
        return nil;
    }
    
    
    dispatcher = [[clazz alloc] initWithTag:tag];
    self.dispatchers[tag] = dispatcher;
    
    return dispatcher;
    
}

- (void)setTaskDirName:(NSString *)taskDirName {
    _taskDirName = taskDirName;
    
    [NSString ensureDirExsit:[NSString toAbsolute:taskDirName]];
}

- (void)setVideoDirName:(NSString *)videoDirName {
    _videoDirName = videoDirName;
    
    [NSString ensureDirExsit:[NSString toAbsolute:videoDirName]];
}

- (NSString *)taskDirURLAbsolutePath {
    
    NSString *tasksDirPath = [NSString toAbsolute:self.taskDirName];
    
    [NSString ensureDirExsit:tasksDirPath];
    
    return tasksDirPath;
}

- (NSString *)videoDirURLAbsolutePath {
    NSString *videoDirPath = [NSString toAbsolute:self.videoDirName];
    [NSString ensureDirExsit:videoDirPath];
    
    return videoDirPath;
}

- (void)addTask:(CDVideoDownloadTask *)task {
    if (![self.allTasks containsObject:task]) {
        [self.allTasks addObject:task];
    }
}

- (void)removeTask:(CDVideoDownloadTask *)task {
    if ([self.allTasks containsObject:task]) {
        [self.allTasks removeObject:task];
        
    }
}

- (void)removeTasksInArray:(NSArray *)tasks {
    [self.allTasks removeObjectsInArray:tasks];
}

- (NSMutableArray *)allTasks {
    if (!_allTasks) {
        _allTasks = [NSMutableArray array];

        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.taskDirURLAbsolutePath error:nil];
        
        @autoreleasepool {
            for (NSString *contentPath in contents) {
                NSString *path = [NSString stringWithFormat:@"%@/%@", self.taskDirURLAbsolutePath, contentPath];
                CDVideoDownloadTask *task = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
                if (task) {
                    
                    [_allTasks addObject:task];
                }
                
            }
        }
        
    }
    
    return _allTasks;
}

- (NSMutableArray<CDVideoDownloadTask *> *)tasksWithTag:(NSString *)tag {
    NSMutableArray *tasks = [NSMutableArray array];
    
    for (CDVideoDownloadTask *task in self.allTasks) {
        if ([task.tags containsObject:tag]) {
            [tasks addObject:task];
        }
    }
    
    return tasks;
    
}

- (CDVideoDownloadTask *)taskWithInfo:(id<CDVideoInfoProvider>)infoProvider {
    __block CDVideoDownloadTask *result = nil;
    NSArray *tasks = [self.allTasks copy];
    [tasks enumerateObjectsUsingBlock:^(CDVideoDownloadTask *task, NSUInteger idx, BOOL *stop) {
        if ([task.videoURLPath isEqualToString:[infoProvider videoURLPath]]) {
            result = task;
            *stop = YES;
        }
    }];
    
    return result;
}


@end
