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
#import "CDVideoBlock.h"


NSString * const CDVideoDownloadStateDidChangedNotif = @"CDVideoDownloadStateDidChangedNotif";
NSString * const CDVideoDownloadStateDidChangedNotifTaskKey = @"CDVideoDownloadStateDidChangedNotifTaskKey";



@interface CDVideoDownloadTask ()

@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, strong) NSURL *localURL;
@property (nonatomic, strong) NSURL *taskURL;
@property (nonatomic) CDVideoDownloadState state;
@property (nonatomic, strong) NSError *error;

@property (nonatomic, strong) NSMutableArray<NSValue *> *loadedBlocks;
@property (nonatomic) int64_t totalBytes;

@property (nonatomic, strong) dispatch_queue_t cache_queue;
@property (nonatomic, strong) AFHTTPSessionManager *httpManager;

@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, strong) NSMutableArray *taskTags;

@end

@implementation CDVideoDownloadTask
@synthesize title;
@synthesize size;
@synthesize duration;

static long long VideoBlockSize = 100000; // in bytes
+ (void)setVideoBlockSize:(long long)size {
    VideoBlockSize = size;
}



- (id)initWithURL:(NSURL *)videoURL localURL:(NSURL *)localURL taskURL:(NSURL *)taskURL {
    self = [super init];
    if (self) {
        self.videoURL = videoURL;
        self.localURL = localURL;
        self.taskURL = taskURL;
        
        self.priority = CDVideoDownloadTaskPriorityMedium;
        
        self.taskTags = [NSMutableArray array];
        
        
        self.cache_queue = dispatch_queue_create([[self.videoURL absoluteString] UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        
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
        self.videoURL = [aDecoder decodeObjectForKey:@"videoURL"];
        self.taskURL = [aDecoder decodeObjectForKey:@"taskURL"];
        self.localURL = [aDecoder decodeObjectForKey:@"localURL"];
        self.priority = [aDecoder decodeIntegerForKey:@"priority"];
        self.offset = [aDecoder decodeInt64ForKey:@"offset"];
        self.totalBytes = [aDecoder decodeInt64ForKey:@"totalBytes"];
        self.loadedBlocks = [aDecoder decodeObjectForKey:@"loadedBlocks"];
        self.taskTags = [aDecoder decodeObjectForKey:@"tags"];
        self.error = [aDecoder decodeObjectForKey:@"error"];
        self.label = [aDecoder decodeObjectForKey:@"label"];
        
        self.cache_queue = dispatch_queue_create([[self.videoURL absoluteString] UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        self.httpManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        self.httpManager.responseSerializer = [AFHTTPResponseSerializer serializer];
        self.httpManager.responseSerializer.acceptableContentTypes = [NSSet setWithObject:@"video/mp4"];
        self.httpManager.completionQueue = self.cache_queue;
        
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    
    [aCoder encodeInteger:self.state forKey:@"state"];
    [aCoder encodeObject:self.videoURL forKey:@"videoURL"];
    [aCoder encodeObject:self.taskURL forKey:@"taskURL"];
    [aCoder encodeObject:self.localURL forKey:@"localURL"];
    [aCoder encodeInteger:self.priority forKey:@"priority"];
    [aCoder encodeInt64:self.offset forKey:@"offset"];
    [aCoder encodeInt64:self.totalBytes forKey:@"totalBytes"];
    [aCoder encodeObject:self.loadedBlocks forKey:@"loadedBlocks"];
    [aCoder encodeObject:self.taskTags forKey:@"taskTags"];
    [aCoder encodeObject:self.error forKey:@"error"];
    [aCoder encodeObject:self.label forKey:@"label"];
    
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
    [NSKeyedArchiver archiveRootObject:self toFile:self.taskURL.absoluteString];
}

- (void)prepare {
    self.state = CDVideoDownloadStateStandby;
    self.loadedBlocks = [NSMutableArray array];
    self.totalBytes = 0;
    
    self.error = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.localURL.absoluteString]) {
        [[NSFileManager defaultManager] removeItemAtURL:self.localURL error:nil];
    }
    
    
    [[NSFileManager defaultManager] createFileAtPath:self.localURL.absoluteString contents:nil attributes:nil];
    
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.localURL.absoluteString];
    
    [self save];
}

- (void)load {
    dispatch_async(self.cache_queue, ^{
        self.state = CDVideoDownloadStateLoading;
        [self notifyStateChanged];
        [self save];
        
        while (true) {
            
            NSValue *firstBlockValue = self.loadedBlocks.firstObject;
            CDVideoBlock firstBlock = {0, 0};
            [firstBlockValue getValue:&firstBlock];
            
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
        NSValue *blockValue = self.loadedVideoBlocks.lastObject;
        CDVideoBlock block;
        [blockValue getValue:&block];
        
        return block.length == self.totalBytes;
    }
}

- (NSArray *)loadedVideoBlocks {
    // 调用者可能使用这个数组做迭代，如果迭代的过程中数组也有update就会导致崩溃，因此这里用了copy
    return [self.loadedBlocks copy];
}

- (CGFloat)progress {
    __block CDVideoBlock block;
    __block long long loadedLength = 0;
    [self.loadedBlocks enumerateObjectsUsingBlock:^(NSValue *blockValue, NSUInteger idx, BOOL *stop) {
        [blockValue getValue:&block];
        loadedLength += block.length;
    }];
    
    NSLog(@"offset %lld, loaded length %lld", self.offset, loadedLength);
    
    
    return ((loadedLength * 1.0) / self.totalBytes);
}

- (void)updateLoadedBlocksWithIncomingBlock:(CDVideoBlock)incomingBlock {
    NSMutableArray<NSValue *> *updatedBlocks = [NSMutableArray array];
    
    __block CDVideoBlock updatedBlock = incomingBlock;
    __block NSValue *updatedBlockValue;
    __block CDVideoBlock loadedBlock;
    
    __block NSInteger mergedSuccessMark = 0;
    
    
    
    if (self.loadedBlocks.count <= 0) {
        updatedBlockValue = [NSValue valueWithBytes:&incomingBlock objCType:@encode(CDVideoBlock)];
        [updatedBlocks addObject:updatedBlockValue];
    } else {
        __weak CDVideoDownloadTask *wself = self;
        [self.loadedBlocks enumerateObjectsUsingBlock:^(NSValue *loadedBlockValue, NSUInteger idx, BOOL *stop) {
            
            [loadedBlockValue getValue:&loadedBlock];
            
            CDVideoBlock mergedBlock = CDVideoBlockMerge(updatedBlock, loadedBlock);
            if (!CDVideoBlockEqual(mergedBlock, CDVideoBlockZero)) {
                updatedBlockValue = [NSValue valueWithBytes:&mergedBlock objCType:@encode(CDVideoBlock)];
                updatedBlock = mergedBlock;
                mergedSuccessMark++;
                
                [updatedBlocks addObject:updatedBlockValue];
            } else {
                
                if (mergedSuccessMark >= 1) {
                    [updatedBlocks addObjectsFromArray:[wself.loadedBlocks subarrayWithRange:NSMakeRange(idx, wself.loadedBlocks.count - 1 - idx)]];
                    *stop = YES;
                } else {
                    
                    if (0 != idx) {
                        NSValue *lastBlockValue = wself.loadedBlocks[idx - 1];
                        CDVideoBlock lastBlock;
                        [lastBlockValue getValue:&lastBlock];
                        if (CDVideoBlockBetween(lastBlock, updatedBlock, loadedBlock)) {
                            [updatedBlocks addObject:updatedBlockValue];
                        }
                    }
                    
                    
                    [updatedBlocks addObject:loadedBlockValue];
                    if (wself.loadedBlocks.count - 1 == idx) {
                        updatedBlockValue = [NSValue valueWithBytes:&incomingBlock objCType:@encode(CDVideoBlock)];
                        [updatedBlocks addObject:updatedBlockValue];
                    }
                }
                
                
                
            }
            
            if (mergedSuccessMark == 2) {
                [updatedBlocks replaceObjectAtIndex:updatedBlocks.count - 1 withObject:updatedBlockValue];
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
    if (self.totalBytes - self.offset < VideoBlockSize * 2) {
        // 剩下不多的话，一次过全部拿回来了
        range = [NSString stringWithFormat:@"bytes=%lld-%lld", self.offset, self.totalBytes];
    } else {
        range = [NSString stringWithFormat:@"bytes=%lld-%lld", self.offset, self.offset + VideoBlockSize];
    }
    
    
    [requestSerializer setValue:range forHTTPHeaderField:@"Range"];
    
    self.httpManager.requestSerializer = requestSerializer;
    
    __weak CDVideoDownloadTask *wself = self;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    NSLog(@"%@ requesting %@, with range %@", self, self.videoURL.absoluteString, range);
    [self.httpManager GET:self.videoURL.absoluteString parameters:nil progress:nil success:^(NSURLSessionDataTask *task, NSData *videoBlock) {
        
        
        [wself updateLoadedBlocksWithIncomingBlock:CDVideoBlockMake(wself.offset, task.countOfBytesReceived)];
        
        [wself.fileHandle seekToFileOffset:wself.offset];
        [wself.fileHandle writeData:videoBlock];
        wself.offset += task.countOfBytesReceived;
        NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
        NSString *contentRange = response.allHeaderFields[@"Content-Range"];
        NSArray *values = [contentRange componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" /"]];
        NSString *totalBytesNum = values.lastObject;
        wself.totalBytes = totalBytesNum.longLongValue;
        NSLog(@"%@ response with range %@", self, contentRange);
        
        [wself save];
        
        
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSURLSessionDataTask *task, NSError *e) {
        NSLog(@"%@ response with error  %@", self, e);
        [wself loadError];
        wself.error = e;
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    if (self.handleDownloadProgress) {
        self.handleDownloadProgress([self progress]);
    }
    
    return;
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
    [[NSFileManager defaultManager] removeItemAtURL:self.localURL error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:self.taskURL error:nil];
    
}

- (void)notifyStateChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CDVideoDownloadStateDidChangedNotif object:nil userInfo:@{CDVideoDownloadStateDidChangedNotifTaskKey: self}];
    });
}

- (BOOL)isEqual:(CDVideoDownloadTask *)task {
    return [self.videoURL isEqual:task.videoURL];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"task: %@, state: %ld", self.label, self.state];
}
@end
