//
//  CDVideoDownloadTask.m
//  CDPlayer
//
//  Created by carusd on 2016/11/29.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "CDVideoDownloadTask.h"
#import "AFNetworking.h"
#import "CDVideoDownloadManager.h"



NSString * const CDVideoDownloadStateDidChangedNotif = @"CDVideoDownloadStateDidChangedNotif";
NSString * const CDVideoDownloadTaskDidHasNewBlockNotif = @"CDVideoDownloadTaskDidHasNewBlockNotif";

NSString * const CDVideoDownloadTaskNotifTaskKey = @"CDVideoDownloadTaskNotifTaskKey";





@interface CDVideoDownloadTask ()

@property (nonatomic, strong) NSString *videoURLPath;
@property (nonatomic, strong) NSString *localURLPath;
@property (nonatomic, strong) NSString *taskURLPath;
@property (nonatomic) CDVideoDownloadState state;
@property (nonatomic, strong) NSError *error;

@property (nonatomic, strong) NSMutableArray<CDVideoBlock *> *loadedBlocks;
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

static long long _VideoBlockSize = 100000; // in bytes
+ (void)setVideoBlockSize:(long long)size {
    _VideoBlockSize = size;
}

+ (long long)VideoBlockSize {
    return _VideoBlockSize;
}

- (id)initWithVideoInfoProvider:(id<CDVideoInfoProvider>)provider taskURLPath:(NSString *)taskURLPath {
    self = [super init];
    if (self) {
        self.infoProvider = provider;
        
        self.videoURLPath = [provider videoURLPath];
        self.localURLPath = [provider localURLPath];
        self.taskURLPath = taskURLPath;
        
        
        self.priority = CDVideoDownloadTaskPriorityMedium;
        
        self.taskTags = [NSMutableArray array];
        
        
        self.cache_queue = dispatch_queue_create([self.videoURLPath UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        
        self.httpManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        self.httpManager.responseSerializer = [AFHTTPResponseSerializer serializer];
        self.httpManager.responseSerializer.acceptableContentTypes = [NSSet setWithObject:@"video/mp4"];
        self.httpManager.completionQueue = self.cache_queue;
        
        
        
        [self prepare];
    }
    
    return self;
}




- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {

        self.state = [aDecoder decodeIntegerForKey:@"state"];
        if (CDVideoDownloadStateLoading == self.state) {
            self.state = CDVideoDownloadStatePause;
        }
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
        
        self.infoProvider = [aDecoder decodeObjectForKey:@"infoProvider"];
        
        self.cache_queue = dispatch_queue_create([self.videoURLPath UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        self.httpManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        self.httpManager.responseSerializer = [AFHTTPResponseSerializer serializer];
        self.httpManager.responseSerializer.acceptableContentTypes = [NSSet setWithObject:@"video/mp4"];
        self.httpManager.completionQueue = self.cache_queue;
        
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
    [aCoder encodeObject:self.infoProvider forKey:@"infoProvider"];
    
}

- (NSString *)absolutePathWithRelativePath:(NSString *)path {
    NSString *prefix = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [NSString stringWithFormat:@"%@/%@", prefix, path];
}

- (long long)sizeInDisk {
    NSString *prefix = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    
    
    NSError *e = nil;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[NSString stringWithFormat:@"%@/%@", prefix, self.localURLPath] error:&e];
    NSLog(@"eeeeeeeeeee  %@", e);
    long long fileSize = [fileAttributes[NSFileSize] longLongValue];
    
    NSDictionary *taskAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[NSString stringWithFormat:@"%@/%@", prefix, self.taskURLPath] error:nil];
    long long taskSize = [taskAttributes[NSFileSize] longLongValue];
    
    return fileSize + taskSize;
}

- (NSArray<NSString *> *)tags {
    return [self.taskTags copy];
}

- (void)addTag:(NSString *)tag {
    [self.taskTags addObject:tag];
}

- (void)removeTag:(NSString *)tag {
    [self.taskTags removeObject:tag];
}

- (void)save {
    [NSKeyedArchiver archiveRootObject:self toFile:[self absolutePathWithRelativePath:self.taskURLPath]];
}

- (void)prepare {
    self.state = CDVideoDownloadStateStandby;
    self.loadedBlocks = [NSMutableArray array];
    self.totalBytes = 0;
    
    self.error = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self absolutePathWithRelativePath:self.localURLPath]]) {
        [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:[self absolutePathWithRelativePath:self.localURLPath]] error:nil];
    }
    
    
    BOOL result = [[NSFileManager defaultManager] createFileAtPath:[self absolutePathWithRelativePath:self.localURLPath] contents:nil attributes:nil];
    if (!result) {
        NSLog(@"create file failed");
    }
    

    
    NSURL *writingURL = [NSURL fileURLWithPath:[self absolutePathWithRelativePath:self.localURLPath]];
    NSError *e = nil;
    self.fileHandle = [NSFileHandle fileHandleForWritingToURL:writingURL error:&e];;
    
    
    [self save];
}

- (void)load {
    dispatch_async(self.cache_queue, ^{
        self.state = CDVideoDownloadStateLoading;
        [self notifyStateChanged];
        [self save];
        
        while (true) {
            self.offset = [self popOffset];
//            CDVideoBlock *blockToBeDownload = [[CDVideoBlock alloc] initWithOffset:self.offset length:[CDVideoDownloadTask VideoBlockSize]];
//            
//            
            
            if (CDVideoDownloadStateLoading == self.state && (self.offset < self.totalBytes || self.totalBytes <= 0)) {
                [self _loadBlock];
            } else {
                break;
            }
        }
        
        if (CDVideoDownloadStateLoading == self.state) {
            self.state = CDVideoDownloadStateLoaded;
            [self notifyStateChanged];
            [self save];
            
            
            // 完整下载好了
            if (self.completelyLoaded) {
                [self finish];
            }
        }
        
    });
    
    
    
}

- (BOOL)completelyLoaded {
    if (self.loadedVideoBlocks.count != 1) {
        return NO;
    } else {
        CDVideoBlock *block = self.loadedVideoBlocks.lastObject;
        
        return block.length == self.totalBytes;
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
        
        
        NSLog(@"loaded offset %f", nVideoBlock.offset);
    }];
    
    return [result copy];
}

- (CGFloat)progress {
    
    __block long long loadedLength = 0;
    [self.loadedBlocks enumerateObjectsUsingBlock:^(CDVideoBlock *block, NSUInteger idx, BOOL *stop) {
        loadedLength += block.length;
    }];
    
//    NSLog(@"offset %lld, loaded length %lld", self.offset, loadedLength);
    
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
                    [updatedBlocks addObjectsFromArray:[wself.loadedBlocks subarrayWithRange:NSMakeRange(idx, wself.loadedBlocks.count - 1 - idx)]];
                    *stop = YES;
                } else {
                    
                    if (0 != idx) {
                        
                        CDVideoBlock *lastBlock = wself.loadedBlocks[idx - 1];
                        if ([updatedBlock between:lastBlock and:loadedBlock]) {
                            [updatedBlocks addObject:updatedBlock];
                        }
                        
                    }
                    
                    [updatedBlocks addObject:loadedBlock];
                    if (wself.loadedBlocks.count - 1 == idx) {
                        [updatedBlocks addObject:updatedBlock];
                    }
                }
                
            }
            
            if (mergedSuccessMark == 2) {
                [updatedBlocks replaceObjectAtIndex:updatedBlocks.count - 1 withObject:updatedBlock];
                [updatedBlocks addObjectsFromArray:[wself.loadedBlocks subarrayWithRange:NSMakeRange(idx + 1, wself.loadedBlocks.count - 1 - (idx + 1))]];
                *stop = YES;
            }
        }];
    }
    
    
    
    self.loadedBlocks = updatedBlocks;
}

- (void)_loadBlock {
    AFHTTPRequestSerializer *requestSerializer = [AFHTTPRequestSerializer serializer];
    requestSerializer.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    
    NSString *range = nil;
    if (self.totalBytes > 0 && self.totalBytes - self.offset < _VideoBlockSize * 2) {
        // 剩下不多的话，一次过全部拿回来了
        range = [NSString stringWithFormat:@"bytes=%lld-%lld", self.offset, self.totalBytes];
    } else {
        range = [NSString stringWithFormat:@"bytes=%lld-%lld", self.offset, self.offset + _VideoBlockSize];
    }
    
    
    [requestSerializer setValue:range forHTTPHeaderField:@"Range"];
    
    self.httpManager.requestSerializer = requestSerializer;
    
    __weak CDVideoDownloadTask *wself = self;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
//    NSLog(@"%@ requesting %@, with range %@", self, self.videoURL.absoluteString, range);
    [self.httpManager GET:self.videoURLPath parameters:nil progress:nil success:^(NSURLSessionDataTask *task, NSData *videoBlock) {
        
        
        
        CDVideoBlock *incomingBlock = [[CDVideoBlock alloc] initWithOffset:wself.offset length:task.countOfBytesReceived];
        [wself updateLoadedBlocksWithIncomingBlock:incomingBlock];
        
        [wself.fileHandle seekToFileOffset:wself.offset];
        NSLog(@"task offset %lld", wself.offset);
        NSLog(@"file offset %lld", wself.fileHandle.offsetInFile);
        [wself.fileHandle writeData:videoBlock];
        wself.offset += task.countOfBytesReceived;
        NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
        NSString *contentRange = response.allHeaderFields[@"Content-Range"];
        NSArray *values = [contentRange componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" /"]];
        NSString *totalBytesNum = values.lastObject;
        wself.totalBytes = totalBytesNum.longLongValue;
//        NSLog(@"%@ response with range %@", self, contentRange);
        
        [wself save];
        
        
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSURLSessionDataTask *task, NSError *e) {
//        NSLog(@"%@ response with error  %@", self, e);
        [wself loadError];
        wself.error = e;
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    if (self.handleDownloadProgress) {
        self.handleDownloadProgress([self progress]);
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadTaskDidHasNewBlockNotif object:nil userInfo:@{CDVideoDownloadTaskNotifTaskKey: self}];
    });
    
    
    return;
}

- (void)pushOffset:(long long)offset {
    self.nextOffset = offset;
}

- (long long)popOffset {
    if (0 == self.nextOffset) {
        return self.offset;
    } else {
        long long result = self.nextOffset;
        self.nextOffset = 0;
        return result;
    }
    
}

- (void)loadError {
    self.state = CDVideoDownloadStateLoadError;
    [self notifyStateChanged];
    [self save];
}

- (void)yield {
    if (CDVideoDownloadStateStandby != self.state && CDVideoDownloadStateLoading != self.state) {
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

- (void)testIntegrated:(void(^)(BOOL))result {
    if (result) {
        result(YES);
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
    
}

- (void)destroy {
    [self pause];
    [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:[self absolutePathWithRelativePath:self.localURLPath]] error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:[self absolutePathWithRelativePath:self.taskURLPath]] error:nil];
    
}

- (void)notifyStateChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadStateDidChangedNotif object:nil userInfo:@{CDVideoDownloadTaskNotifTaskKey: self}];
    });
}

- (BOOL)isEqual:(CDVideoDownloadTask *)task {
    return [self.videoURLPath isEqualToString:task.videoURLPath];
    
}

- (NSString *)description {
    return [NSString stringWithFormat:@"task: %@, state: %lld", self.label, self.state];
}
@end
