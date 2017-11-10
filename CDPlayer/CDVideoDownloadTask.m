//
//  CDVideoDownloadTask.m
//  CDPlayer
//
//  Created by carusd on 2016/11/29.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "CDVideoDownloadTask.h"
#import "NSString+CDFilePath.h"
#import "CDVideoDownloadManager.h"
#import "FileHash.h"
#import "AFNetworking.h"


NSString * const CDVideoDownloadErrorDomain = @"com.carusd.player.task.error";

NSString * const CDVideoDownloadStateDidChangedNotif = @"CDVideoDownloadStateDidChangedNotif";
NSString * const CDVideoDownloadTaskDidHasNewBlockNotif = @"CDVideoDownloadTaskDidHasNewBlockNotif";
NSString * const CDVideoDownloadTaskInconsistenceNotif = @"CDVideoDownloadTaskInconsistenceNotif";

NSString * const CDVideoDownloadTaskNotifTaskKey = @"CDVideoDownloadTaskNotifTaskKey";
NSString * const CDVideoDownloadTaskNotifRequestRangeKey = @"CDVideoDownloadTaskNotifRequestRangeKey";
NSString * const CDVideoDownloadTaskNotifResponseRangeKey = @"CDVideoDownloadTaskNotifResponseRangeKey";

NSString * const CDVideoDownloadBackgroundSessionIdentifier = @"CDVideoDownloadBackgroundSessionIdentifier";

#define DefaultDownloadSize (100000)

@interface CDVideoDownloadTask ()

@property (nonatomic, strong) NSString *videoURLPath;
@property (nonatomic, strong) NSString *localURLPath;
@property (nonatomic, strong) NSString *taskURLPath;
@property (nonatomic) CDVideoDownloadState state;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, copy) NSString *videoFileMD5;

@property (nonatomic, strong) NSMutableArray<CDVideoBlock *> *loadedBlocks;

@property (nonatomic) int64_t offset;
@property (nonatomic) int64_t totalBytes;

@property (nonatomic, strong) dispatch_queue_t cache_queue;
@property (nonatomic, strong) AFHTTPSessionManager *httpManager;

@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, strong) NSMutableArray *taskTags;

@property (nonatomic, strong) id<CDVideoInfoProvider> infoProvider;

@property (nonatomic) long long nextOffset; // 下一次下载，从这里开始
@end

@implementation CDVideoDownloadTask
@synthesize title;
@synthesize size;
@synthesize duration;

static long long _VideoBlockSize = DefaultDownloadSize; // in bytes
static NSString * _CachePath;
static NSString * _CacheDirectoryName;

#pragma block size
+ (void)setVideoBlockSize:(long long)size {
    _VideoBlockSize = size;
}

+ (long long)VideoBlockSize {
    return _VideoBlockSize;
}

+ (void)resetVideoBlockSize {
    _VideoBlockSize = DefaultDownloadSize;
}

- (void)dealloc {
    [_httpManager invalidateSessionCancelingTasks:YES];
}

- (id)initWithVideoInfoProvider:(id<CDVideoInfoProvider>)provider taskURLPath:(NSString *)taskURLPath {
    self = [super init];
    if (self) {
        
        self.state = CDVideoDownloadStateInit;
        
        self.infoProvider = provider;
        
        self.videoURLPath = [provider videoURLPath];
        self.localURLPath = [provider localURLPath];
        self.taskURLPath = taskURLPath;
        
        self.priority = CDVideoDownloadTaskPriorityMedium;
        
        self.taskTags = [NSMutableArray array];
        
        
        self.cache_queue = dispatch_queue_create([self.videoURLPath UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        
        self.httpManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        self.httpManager.responseSerializer = [AFHTTPResponseSerializer serializer];
        self.httpManager.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"video/mp4", @"text/html", @"application/octet-stream", nil];
        self.httpManager.completionQueue = self.cache_queue;
        
        self.createTime = [[NSDate date] timeIntervalSince1970];
        
        self.loadedBlocks = [NSMutableArray array];
        self.totalBytes = 0;
        
        self.nextOffset = -1;
        
        self.error = nil;
        self.videoFileMD5 = @"";
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:self.completeLocalPath]) {
            [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:self.completeLocalPath] error:nil];
        }
        
        
        [[NSFileManager defaultManager] createFileAtPath:self.completeLocalPath contents:nil attributes:nil];
        
        NSURL *writingURL = [NSURL fileURLWithPath:self.completeLocalPath];
        NSError *e = nil;
        self.fileHandle = [NSFileHandle fileHandleForWritingToURL:writingURL error:&e];
        if (!self.fileHandle) {
            NSLog(@"creating file handle error %@", e);
            NSError *error = [[NSError alloc] initWithDomain:CDVideoDownloadErrorDomain code:CDVideoDownloadTaskErrorCodeCreateFileHandleError userInfo:@{NSLocalizedDescriptionKey: @"cannot create writing file handle"}];
            [self encounterError:error];
            
        } else {
            [self prepare];
        }
        
        
    }
    
    return self;
}




- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {

        self.videoURLPath = [aDecoder decodeObjectForKey:@"videoURLPath"];
        self.taskURLPath = [aDecoder decodeObjectForKey:@"taskURLPath"];
        self.localURLPath = [aDecoder decodeObjectForKey:@"localURLPath"];
        self.priority = [aDecoder decodeIntegerForKey:@"priority"];
        self.offset = [aDecoder decodeInt64ForKey:@"offset"];
        self.totalBytes = [aDecoder decodeInt64ForKey:@"totalBytes"];
        self.loadedBlocks = [aDecoder decodeObjectForKey:@"loadedBlocks"];
        self.taskTags = [aDecoder decodeObjectForKey:@"taskTags"];
        self.error = [aDecoder decodeObjectForKey:@"error"];
        self.label = [aDecoder decodeObjectForKey:@"label"];
        self.createTime = [aDecoder decodeDoubleForKey:@"createTime"];
        self.videoFileMD5 = [aDecoder decodeObjectForKey:@"videoFileMD5"];
        
        self.infoProvider = [aDecoder decodeObjectForKey:@"infoProvider"];
        
        self.state = [aDecoder decodeIntegerForKey:@"state"];
        if (CDVideoDownloadStateLoading == self.state) {
            self.state = CDVideoDownloadStatePause;
        } else if (CDVideoDownloadStateFinished == self.state) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:self.completeLocalPath]) {
                self.state = CDVideoDownloadStateInit;
                self.loadedBlocks = [NSMutableArray array];
                self.totalBytes = 0;
                self.nextOffset = -1;
                self.error = nil;
                self.videoFileMD5 = @"";
                
                [[NSFileManager defaultManager] createFileAtPath:self.completeLocalPath contents:nil attributes:nil];
            }
            
        }
        
        if (CDVideoDownloadStateFinished != self.state) {
            self.cache_queue = dispatch_queue_create([self.videoURLPath UTF8String], DISPATCH_QUEUE_CONCURRENT);
            
            self.httpManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
            self.httpManager.responseSerializer = [AFHTTPResponseSerializer serializer];
            self.httpManager.responseSerializer.acceptableContentTypes = [NSSet setWithObjects:@"video/mp4", @"text/html", @"application/octet-stream", nil];
            self.httpManager.completionQueue = self.cache_queue;
            
            NSURL *writingURL = [NSURL fileURLWithPath:self.completeLocalPath];
            NSError *e = nil;
            self.fileHandle = [NSFileHandle fileHandleForWritingToURL:writingURL error:&e];
        }
        
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    
    [aCoder encodeInteger:self.state forKey:@"state"];
    [aCoder encodeObject:self.videoURLPath forKey:@"videoURLPath"];
    [aCoder encodeObject:self.taskURLPath forKey:@"taskURLPath"];
    [aCoder encodeObject:self.localURLPath forKey:@"localURLPath"];
    [aCoder encodeInteger:self.priority forKey:@"priority"];
    [aCoder encodeInt64:self.offset forKey:@"offset"];
    [aCoder encodeInt64:self.totalBytes forKey:@"totalBytes"];
    [aCoder encodeObject:self.loadedBlocks forKey:@"loadedBlocks"];
    [aCoder encodeObject:self.taskTags forKey:@"taskTags"];
    [aCoder encodeObject:self.error forKey:@"error"];
    [aCoder encodeObject:self.label forKey:@"label"];
    [aCoder encodeDouble:self.createTime forKey:@"createTime"];
    [aCoder encodeObject:self.videoFileMD5 forKey:@"videoFileMD5"];
    [aCoder encodeObject:self.infoProvider forKey:@"infoProvider"];
    
    
}

- (NSString *)completeLocalPath {
    return [NSString toAbsolute:self.localURLPath];
}

- (long long)sizeInDisk {
    NSError *e = nil;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.completeLocalPath error:&e];
    
    long long fileSize = [fileAttributes[NSFileSize] longLongValue];
    
    NSDictionary *taskAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.completeLocalPath error:nil];
    long long taskSize = [taskAttributes[NSFileSize] longLongValue];
    
    return fileSize + taskSize;
}

#pragma mark tag
- (NSArray<NSString *> *)tags {
    return [self.taskTags copy];
}

- (void)addTag:(NSString *)tag {
    [self.taskTags addObject:tag];
}

- (void)removeTag:(NSString *)tag {
    [self.taskTags removeObject:tag];
}

#pragma mark fsm

- (void)notifyStateChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadStateDidChangedNotif object:nil userInfo:@{CDVideoDownloadTaskNotifTaskKey: self}];
    });
}


- (void)save {
    [NSKeyedArchiver archiveRootObject:self toFile:[NSString toAbsolute:self.taskURLPath]];
}

- (void)prepare {
    self.state = CDVideoDownloadStatePreparing;
    [self notifyStateChanged];
    [self save];
    
//    dispatch_async(self.cache_queue, ^{
//        [self pushOffset:0];
//        _VideoBlockSize = 2;
//        [self _loadBlock];
//        [CDVideoDownloadTask resetVideoBlockSize];
//        
//        dispatch_async(dispatch_get_main_queue(), ^{
            [self standby];
//        });
//    });
    
}

- (void)standby {
    self.state = CDVideoDownloadStateStandby;
    [self notifyStateChanged];
    [self save];
    
}


- (void)_loadBlock {
    AFHTTPRequestSerializer *requestSerializer = [AFHTTPRequestSerializer serializer];
    requestSerializer.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    
    NSString *range = [NSString stringWithFormat:@"bytes=%lld-%lld", self.offset, self.offset + _VideoBlockSize];
    long long requestStart = self.offset;
    long long requestEnd = self.offset + _VideoBlockSize;
    
    [requestSerializer setValue:range forHTTPHeaderField:@"Range"];
    
    self.httpManager.requestSerializer = requestSerializer;
    
    __weak CDVideoDownloadTask *wself = self;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    //    NSLog(@"%@ requesting %@, with range %@, with total %lld", self, self.videoURLPath, range, self.totalBytes);
    
    [self.httpManager GET:self.videoURLPath parameters:nil progress:nil success:^(NSURLSessionDataTask *task, NSData *videoBlock) {
        
        
        CDVideoBlock *incomingBlock = [[CDVideoBlock alloc] initWithOffset:wself.offset length:task.countOfBytesReceived];
        [wself updateLoadedBlocksWithIncomingBlock:incomingBlock];
        
        [wself.fileHandle seekToFileOffset:wself.offset];
        //            NSLog(@"file offset %lld", wself.fileHandle.offsetInFile);
        
        [wself.fileHandle writeData:videoBlock];
        [wself.fileHandle synchronizeFile];
        wself.offset += task.countOfBytesReceived;
        NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
        NSString *contentRange = response.allHeaderFields[@"Content-Range"];
        NSArray *values = [contentRange componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" /"]];
        
        NSString *totalBytesNum = values.lastObject;
        wself.totalBytes = totalBytesNum.longLongValue;
        
        if (values.count > 1) { // for safety
            NSString *realRangeStr = values[1];
            NSArray *realRangeArr = [realRangeStr componentsSeparatedByString:@"-"];
            long long responseStart = [realRangeArr.firstObject longLongValue];
            long long responseEnd = [realRangeArr.lastObject longLongValue];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (responseEnd != wself.totalBytes && responseEnd != wself.totalBytes - 1) {
                    if (requestStart != responseStart || requestEnd != responseEnd) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadTaskInconsistenceNotif object:wself userInfo:@{CDVideoDownloadTaskNotifTaskKey: wself, CDVideoDownloadTaskNotifRequestRangeKey: range, CDVideoDownloadTaskNotifResponseRangeKey: contentRange}];
                    }
                } else {
                    if (requestStart != responseStart) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadTaskInconsistenceNotif object:wself userInfo:@{CDVideoDownloadTaskNotifTaskKey: wself, CDVideoDownloadTaskNotifRequestRangeKey: range, CDVideoDownloadTaskNotifResponseRangeKey: contentRange}];
                    }
                }
            });
        }
        
        [wself save];
        
        
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSURLSessionDataTask *task, NSError *e) {
        NSError *error = nil;
        if (CDVideoDownloadStatePreparing == wself.state) {
            error = [[NSError alloc] initWithDomain:CDVideoDownloadErrorDomain code:CDVideoDownloadTaskErrorCodePrepareLoadError userInfo:@{NSLocalizedDescriptionKey: @"prepare load error"}];
        } else if (CDVideoDownloadStateLoading == wself.state) {
            error = [[NSError alloc] initWithDomain:CDVideoDownloadErrorDomain code:CDVideoDownloadTaskErrorCodeLoadError userInfo:@{NSLocalizedDescriptionKey: @"load error"}];
        }
        wself.error = error;
        [wself loadError];
        [wself encounterError:error];
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    if (self.handleDownloadProgress) {
        self.handleDownloadProgress([self progress]);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadTaskDidHasNewBlockNotif object:nil userInfo:@{CDVideoDownloadTaskNotifTaskKey: self}];
    });
    
    
    sleep((unsigned int)self.frequency);
    
    return;
}

- (void)load {
    self.state = CDVideoDownloadStateLoading;
    [self notifyStateChanged];
    [self save];
    dispatch_async(self.cache_queue, ^{
        
        while (true) {
            self.offset = [self popOffset];
//            NSLog(@"requesting offset %lld", self.offset);
            // 跳过已经下载好的部分
            __weak CDVideoDownloadTask *wself = self;
            [self.loadedBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *block, NSUInteger idx, BOOL *stop) {
                if ([block containsPosition:wself.offset]) {
                    wself.offset = block.offset + block.length;
                    [wself save];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (CDVideoDownloadStateLoading == wself.state) {
                            [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadTaskDidHasNewBlockNotif object:nil userInfo:@{CDVideoDownloadTaskNotifTaskKey: wself}];
                        }
                        
                    });
                    
                    *stop = YES;
                }
                
            }];
            
            if (CDVideoDownloadStateLoading == self.state && (self.offset < self.totalBytes || self.totalBytes <= 0)) {
                [self _loadBlock];
            } else {
                break;
            }
        }
        
        if (CDVideoDownloadStateLoading == self.state && -1 == self.nextOffset) {
//            NSLog(@"loaded");
            self.state = CDVideoDownloadStateLoaded;
            [self notifyStateChanged];
            [self save];
            
            // 完整下载好了
            
            if ([self testIntegrated]) {
                [self finish];
            }
            
        }
        
    });
    
}

- (void)loadError {
    self.state = CDVideoDownloadStateLoadError;
    [self notifyStateChanged];
    [self save];
}

- (void)encounterError:(NSError *)e {
    self.error = e;
    self.state = CDVideoDownloadStateError;
    [self notifyStateChanged];
    [self save];
}

- (void)yield {
    if (CDVideoDownloadStatePause != self.state && CDVideoDownloadStateStandby != self.state && CDVideoDownloadStateLoading != self.state && CDVideoDownloadStateLoadError != self.state && CDVideoDownloadStateError != self.state) {
        return;
    }
    self.state = CDVideoDownloadStateWaiting;
    [self notifyStateChanged];
    [self save];
}

- (void)pause {
    if (CDVideoDownloadStateLoading != self.state && CDVideoDownloadStateWaiting != self.state) {
        
        return;
    }
    self.state = CDVideoDownloadStatePause;
    [self notifyStateChanged];
    [self save];
}

- (BOOL)testIntegrated {
    if (self.infoProvider.md5.length > 0) {
        NSString *md5 = [FileHash md5HashOfFileAtPath:self.completeLocalPath];
        BOOL integrated = NO;
        if ([md5 isEqualToString:[self.infoProvider md5]]) {
            integrated = YES;
        }
        self.videoFileMD5 = md5;
        return integrated;
    } else {
        return [self completelyLoaded];
    }
    
}


- (void)finish {
    if (CDVideoDownloadStateLoaded != self.state) {
        return;
    }
    
    [self.httpManager invalidateSessionCancelingTasks:YES];
    
    [self.fileHandle closeFile];
    
    self.state = CDVideoDownloadStateFinished;
    [self notifyStateChanged];
    [self save];
    
//    NSDictionary *info = [[NSFileManager defaultManager] attributesOfItemAtPath:[NSString toAbsolute:self.localURLPath] error:nil];
    //    NSLog(@"finished video size %@", info);
    
}

- (void)destroy {
    [self pause];
    [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:self.completeLocalPath] error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:[NSString toAbsolute:self.taskURLPath]] error:nil];
    
}

#pragma mark video block


- (BOOL)completelyLoaded {
    if ([self.infoProvider md5].length > 0) {
        if ([self.videoFileMD5 isEqualToString:[self.infoProvider md5]]) {
            return YES;
        } else {
            return NO;
        }
    } else {
        if (self.loadedVideoBlocks.count != 1) {
            return NO;
        } else {
            CDVideoBlock *block = self.loadedVideoBlocks.lastObject;
            
            return block.length == self.totalBytes;
        }
    }
    
}

- (NSArray<CDVideoBlock *> *)loadedVideoBlocks {
    // 调用者可能使用这个数组做迭代，如果迭代的过程中数组也有update就会导致崩溃，因此这里用了copy
    return [self.loadedBlocks copy];
}

- (NSArray<CDVideoNormalizedBlock *> *)loadedVideoRanges {
    if (0 == self.totalBytes) {
        return nil;
    }
    NSArray *videoblocks = [self loadedVideoBlocks];
    NSMutableArray *result = [NSMutableArray array];
    [videoblocks enumerateObjectsUsingBlock:^(CDVideoBlock *videoBlock, NSUInteger idx, BOOL *stop) {
        CDVideoNormalizedBlock *nVideoBlock = [[CDVideoNormalizedBlock alloc] init];
        nVideoBlock.offset = videoBlock.offset * 1.0 / self.totalBytes;
        nVideoBlock.length = videoBlock.length * 1.0 / self.totalBytes;
        
        [result addObject:nVideoBlock];
        
    }];
    
    return [result copy];
}

- (CGFloat)progress {
    
    __block long long loadedLength = 0;
    [self.loadedBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *block, NSUInteger idx, BOOL *stop) {
        loadedLength += block.length;
    }];
    
    
    
    if (0 == self.totalBytes) {
        return self.totalBytes;
    } else {
        return ((loadedLength * 1.0) / self.totalBytes);
    }
    
}

- (void)updateLoadedBlocksWithIncomingBlock:(CDVideoBlock *)incomingBlock {
    NSMutableArray<CDVideoBlock *> *updatedBlocks = [NSMutableArray array];
    
    __block CDVideoBlock *updatedBlock = incomingBlock;
    
    
    __block NSInteger mergedSuccessMark = 0;
    
    
    
    if (self.loadedBlocks.count <= 0) {
        
        [updatedBlocks addObject:updatedBlock];
    } else {
        __weak CDVideoDownloadTask *wself = self;
        [self.loadedBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *loadedBlock, NSUInteger idx, BOOL *stop) {
            
            CDVideoBlock *mergedBlock = [updatedBlock blockWithMergingBlock:loadedBlock];
            
            if ([mergedBlock isValid]) {
                updatedBlock = mergedBlock;
                mergedSuccessMark++;
                
                [updatedBlocks addObject:updatedBlock];
            } else {
                
                if (mergedSuccessMark >= 1) {
                    [updatedBlocks addObjectsFromArray:[wself.loadedBlocks subarrayWithRange:NSMakeRange(idx, wself.loadedBlocks.count - idx)]];
                    *stop = YES;
                } else {
                    
                    if (0 != idx) {
                        
                        CDVideoBlock *lastBlock = wself.loadedBlocks[idx - 1];
                        if ([updatedBlock between:lastBlock and:loadedBlock]) {
                            [updatedBlocks addObject:updatedBlock];
                            
                            [updatedBlocks addObjectsFromArray:[wself.loadedBlocks subarrayWithRange:NSMakeRange(idx, wself.loadedBlocks.count - idx)]];
                            *stop = YES;
                            
                        } else {
                            if (wself.loadedBlocks.count - 1 == idx) {
                                [updatedBlocks addObject:updatedBlock];
                            }else {
                                [updatedBlocks addObject:loadedBlock];
                            }
                        }
                    } else {
                        [updatedBlocks addObject:loadedBlock];
                        if (wself.loadedBlocks.count - 1 == idx) {
                            [updatedBlocks addObject:updatedBlock];
                        }
                    }
                }
            }
            
            if (mergedSuccessMark == 2) {
                [updatedBlocks removeObjectAtIndex:updatedBlocks.count - 2];
                if (idx < wself.loadedBlocks.count - 1) {
                    [updatedBlocks addObjectsFromArray:[wself.loadedBlocks subarrayWithRange:NSMakeRange(idx + 1, wself.loadedBlocks.count - (idx + 1))]];
                }
                
                *stop = YES;
            }
        }];
    }
    
    
    
    self.loadedBlocks = updatedBlocks;
}



- (void)pushOffset:(long long)offset {
    self.nextOffset = offset;
}

- (long long)popOffset {
    if (-1 == self.nextOffset) {
        return self.offset;
    } else {
        long long result = self.nextOffset;
        self.nextOffset = -1;
        return result;
    }
    
}


#pragma mark meta
- (BOOL)isEqual:(CDVideoDownloadTask *)task {
    return [self.videoURLPath isEqualToString:task.videoURLPath];
    
}

- (NSString *)description {
    return [NSString stringWithFormat:@"task: %@, video url %@, state: %lld", self.label, self.videoURLPath, self.state];
}
@end
