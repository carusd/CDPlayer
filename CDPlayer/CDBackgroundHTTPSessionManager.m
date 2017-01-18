//
//  CDBackgroundHTTPSessionManager.m
//  Pods
//
//  Created by carusd on 2017/1/17.
//
//

#import "CDBackgroundHTTPSessionManager.h"

static NSString * const kBackgroundSessionIdentifier = @"com.carusd.backgroundsession";

@implementation CDBackgroundHTTPSessionManager

+ (instancetype)sharedManager
{
    static id sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
    });
    return sharedMyManager;
}

- (instancetype)init
{
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:kBackgroundSessionIdentifier];
    self = [super initWithSessionConfiguration:configuration];
    if (self) {
        [self configureDownloadFinished];
        [self configureBackgroundSessionFinished];
    }
    return self;
}

- (void)configureDownloadFinished
{
    // just save the downloaded file to documents folder using filename from URL
    
    [self setDownloadTaskDidFinishDownloadingBlock:^NSURL *(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *location) {
        if ([downloadTask.response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSInteger statusCode = [(NSHTTPURLResponse *)downloadTask.response statusCode];
            if (statusCode != 200) {
                // handle error here, e.g.
                
                NSLog(@"%@ failed (statusCode = %ld)", [downloadTask.originalRequest.URL lastPathComponent], statusCode);
                return nil;
            }
        }
        
        NSString *filename      = [downloadTask.originalRequest.URL lastPathComponent];
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        NSString *path          = [documentsPath stringByAppendingPathComponent:filename];
        return [NSURL fileURLWithPath:path];
    }];
    
    [self setTaskDidCompleteBlock:^(NSURLSession *session, NSURLSessionTask *task, NSError *error) {
        if (error) {
            // handle error here, e.g.,
            
            NSLog(@"%@: %@", [task.originalRequest.URL lastPathComponent], error);
        }
    }];
}

- (void)configureBackgroundSessionFinished
{
    typeof(self) __weak weakSelf = self;
    
    [self setDidFinishEventsForBackgroundURLSessionBlock:^(NSURLSession *session) {
//        if (weakSelf.savedCompletionHandler) {
//            weakSelf.savedCompletionHandler();
//            weakSelf.savedCompletionHandler = nil;
//        }
    }];
}



@end
