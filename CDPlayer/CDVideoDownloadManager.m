//
//  CDVideoDownloadManager.m
//  CDPlayer
//
//  Created by carusd on 2016/11/29.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "CDVideoDownloadManager.h"
#import "CDVideoDownloadMegaManager.h"
#import "CDVideoDownloadTask.h"
#import <objc/runtime.h>

@interface CDVideoDownloadManager ()

@property (nonatomic, weak) id<CDVideoDownloadTaskPersistenceManager> persistenceManager;
@property (nonatomic, strong) NSMutableArray<CDVideoDownloadTask *> *tasks;

@property (nonatomic, copy) NSString *tag;
@end

@implementation CDVideoDownloadManager
@synthesize maxConcurrentNum;
@synthesize tasks = _tasks;

- (id)initWithTag:(NSString *)tag {
    self = [super init];
    if (self) {
        self.tag = tag;
        
        self.maxConcurrentNum = 3;
        
        self.persistenceManager = [CDVideoDownloadMegaManager sharedInstance];
        self.tasks = [self.persistenceManager tasksWithTag:self.tag];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleTaskStateChanged:) name:CDVideoDownloadStateDidChangedNotif object:nil];
        
    }
    
    return self;
}

- (void)handleTaskStateChanged:(NSNotification *)notif {
    CDVideoDownloadTask *task = notif.userInfo[CDVideoDownloadTaskNotifTaskKey];
    if (CDVideoDownloadStateFinished == task.state ||
        CDVideoDownloadStateLoaded == task.state ||
        CDVideoDownloadStateLoadError == task.state) {
        if (self.loadingTasks.count < self.maxConcurrentNum && [task.tags containsObject:self.tag] && CDVideoDownloadTaskPriorityMedium == task.priority) {
            if (![self loadNextWaitingTask] && 0 == self.loadingTasks.count) {
                // 只执行一次
                if (self.allTasksDidStopped) {
                    self.allTasksDidStopped();
                    self.allTasksDidStopped = nil;
                }
            }
        }
        
    }
    
//    NSLog(@"tag %@", self.tag);
//    
//    NSLog(@"loading tasks %@", [self loadingTasks]);
//    NSLog(@"finished tasks %@", [self finishedTasks]);
    
    
}

- (void)launchLoading {
    __weak CDVideoDownloadManager *wself = self;
    [self.tasks enumerateObjectsUsingBlock:^(CDVideoDownloadTask *task, NSUInteger idx, BOOL *stop) {
        [wself tryToStartTask:task];
    }];
}

- (CDVideoDownloadTask *)loadNextWaitingTask {
    
    __block CDVideoDownloadTask *nextTask = nil;
    
    
    [self.allTasks enumerateObjectsUsingBlock:^(CDVideoDownloadTask *task, NSUInteger idx, BOOL *stop) {
        if (CDVideoDownloadStateWaiting == task.state) {
            [task load];
            *stop = YES;
            nextTask = task;
        }
        
    }];
    
    return nextTask;
}



// 普通优先级的任务只允许maxConcurrentNum个并行，最高优先级(Immediate)只允许一个并行
// 实际上，是3+1个并行
- (void)tryToStartTask:(CDVideoDownloadTask *)task {
    if (CDVideoDownloadStateLoading == task.state || CDVideoDownloadStateFinished == task.state) {
        return;
    }
    if (self.loadingTasks.count < self.maxConcurrentNum) {
        
        [task load];
        
    } else if (CDVideoDownloadTaskPriorityImmediate == task.priority){
        
        NSArray *loadingTasks = [self loadingTasks];
        for (CDVideoDownloadTask *loadingTask in loadingTasks) {
            if (CDVideoDownloadTaskPriorityImmediate == loadingTask.priority) {
                // 因为有新的immediate任务进队，而该状态任意时间只能允许一个任务存在，因此旧任务要被降级
                loadingTask.priority = CDVideoDownloadTaskPriorityMedium;
            }
        }
        [loadingTasks.firstObject yield];
        
        [task load];
    } else {
        [task yield];
    }
}

- (void)addTask:(CDVideoDownloadTask *)task {
    if (![self.tasks containsObject:task]) {
        [self.tasks addObject:task];
        [self.persistenceManager addTask:task];
        
        
        // 自动清理
        if (self.tasks.count > 30) {
            
            CDVideoDownloadTask *lastTask = self.tasks.firstObject;
            [self removeTask:lastTask];
        }
        
    }
}

- (void)removeTask:(CDVideoDownloadTask *)task {
    if ([self.tasks containsObject:task]) {
        [task removeTag:self.tag];
        [self.tasks removeObject:task];
        
        NSLog(@"remove %@ from tag %@", task, self.tag);
        
        if (task.tags.count <= 0) {
            [task destroy];
            [self.persistenceManager removeTask:task];
            NSLog(@"destroy %@", task);
        }
    }
}

- (void)removeTaskWithInfoProvider:(id<CDVideoInfoProvider>)provider {
    CDVideoDownloadTask *task = [self taskWithInfo:provider];
    if (task) {
        [self removeTask:task];
    }
}

- (BOOL)containsTask:(CDVideoDownloadTask *)task {
    return [self.tasks containsObject:task];
}

- (CDVideoDownloadTask *)taskWithInfo:(id<CDVideoInfoProvider>)provider {
    for (CDVideoDownloadTask *task in self.tasks) {
        if ([task.videoURLPath isEqualToString:[provider videoURLPath]]) {
            return task;
        }
    }
    return nil;
}

- (CDVideoDownloadTask *)makeTaskWithInfo:(id<CDVideoInfoProvider>)provider {
    CDVideoDownloadTask *task = [self taskWithInfo:provider];
    if (task) {
        return task;
    }
    
    NSString *filename = [[[provider videoURLPath] lastPathComponent] stringByDeletingPathExtension];
    
    NSString *taskURLPath = [NSString stringWithFormat:@"%@/%@", [self.persistenceManager cacheDirURLPath], filename];
    
    
    task = [[CDVideoDownloadTask alloc] initWithVideoInfoProvider:provider taskURLPath:taskURLPath];
    task.label = [provider title];
    [task addTag:self.tag];
    
    [self addTask:task];
    return task;
}

- (NSArray<CDVideoDownloadTask *> *)finishedTasks {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"state == %ld", (long)CDVideoDownloadStateFinished];
    
    NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:@"createTime"
                                                                 ascending:YES];
    
    NSArray *f = [[self.tasks filteredArrayUsingPredicate:predicate] sortedArrayUsingDescriptors:@[descriptor]];
    
    
    return f;
}

- (NSArray<CDVideoDownloadTask *> *)loadingTasks {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"state == %ld", (long)CDVideoDownloadStateLoading];
    return [self.tasks filteredArrayUsingPredicate:predicate];
}

- (NSArray<CDVideoDownloadTask *> *)allTasks {
    return self.tasks;
}

- (BOOL)loading {
    return self.loadingTasks.count > 0;
}

- (void)setClearTasksGroup:(dispatch_group_t)clearTasksGroup {
    objc_setAssociatedObject(self, (__bridge const void *)@"clearTasksGroup", clearTasksGroup, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (dispatch_group_t)clearTasksGroup {
    return objc_getAssociatedObject(self, (__bridge const void *)@"clearTasksGroup");
}

- (void)clearTasks:(void (^)(void))completion {
    [self pauseAllLoadingTasks];
    
    dispatch_queue_t clearTasksQueue = dispatch_queue_create("com.caursd.CDPlayer.clearTasks", DISPATCH_QUEUE_SERIAL);
    
    void(^clear)(void) = ^{
        for (CDVideoDownloadTask *task in self.tasks) {
            [task removeTag:self.tag];
            
            if (task.tags.count <= 0) {
                [task destroy];
                [self.persistenceManager removeTask:task];
            }
        }
        
        self.tasks = [NSMutableArray array];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion();
            }
        });
    };
    
    if (self.clearTasksGroup) {
        dispatch_group_async(self.clearTasksGroup, clearTasksQueue, ^{
            clear();
        });
    } else {
        dispatch_async(clearTasksQueue, ^{
            clear();
        });
    }
    
    
}

- (long long)sizeInDisk {
    __block long long result = 0;
    [self.tasks enumerateObjectsUsingBlock:^(CDVideoDownloadTask *task, NSUInteger idx, BOOL *stop) {
        
        
        result += [task sizeInDisk];
    }];
    
    return result;
}

- (void)pauseAllLoadingTasks {
    [self.allTasks makeObjectsPerformSelector:@selector(pause)];
    
}

@end
