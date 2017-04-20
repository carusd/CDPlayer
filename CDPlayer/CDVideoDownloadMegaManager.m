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

NSString * const CDVideoDownloadDirURLDidChanged = @"CDVideoDownloadDirURLDidChanged";

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
        
        
        [self setCacheDirURLPath:@"com.carusd.videotask"];
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

- (void)setCacheDirURLPath:(NSString *)path {
    _cacheDirURLPath = path;
    NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *tasksDirPath = [NSString stringWithFormat:@"%@/%@", cachePath, self.cacheDirURLPath];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:tasksDirPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:tasksDirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadDirURLDidChanged object:nil];
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
        
        
        NSString *cachePath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *tasksDirPath = [NSString stringWithFormat:@"%@/%@", cachePath, self.cacheDirURLPath];
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tasksDirPath error:nil];
        
        for (NSString *contentPath in contents) {
            NSString *path = [NSString stringWithFormat:@"%@/%@", tasksDirPath, contentPath];
            CDVideoDownloadTask *task = [NSKeyedUnarchiver unarchiveObjectWithFile:path];
            if (task) {
                [_allTasks addObject:task];
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
