//
//  CDTestDefaultManager.m
//  CDPlayer
//
//  Created by carusd on 2016/12/8.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "CDPlayerKit.h"
#import "CDVideo.h"




@interface CDTestDefaultManager : XCTestCase

@property (nonatomic, strong) CDVideoDownloadManager *manager;
@property (nonatomic, strong) NSArray<NSString *> *videoPaths;

@end

@implementation CDTestDefaultManager

- (NSString *)tag {
    return @"test";
}

- (void)setUp {
    [super setUp];
    
    self.manager = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:[self tag] class:nil];
    NSString *paths = [NSString stringWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"plainvideos" ofType:@""] encoding:NSUTF8StringEncoding error:nil];
    self.videoPaths = [paths componentsSeparatedByString:@"\n"];
    
    
}



- (void)tearDown {
    
    [super tearDown];
}

- (void)testDefaultManager {
    id<CDVideoDownloadTaskDispatcher> dispatcher = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:@"hellodispatcher" class:nil];
    
    XCTAssert([dispatcher isKindOfClass:[CDVideoDownloadManager class]]);
}

- (void)testSingleInstance {
    CDVideoDownloadManager *manager = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:[self tag] class:nil];
    
    XCTAssert(manager == self.manager);
}



- (void)testAddTask {
    
    CDVideo *video = [[CDVideo alloc] init];
    video.videoURLPath = self.videoPaths.firstObject;
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    while (true) {
        if (CDVideoDownloadStateFinished == task.state) {
            break;
        }
    }
    
    XCTAssert(task.completelyLoaded);
}

- (void)testVideoIntegratedWithMD5 {
    CDVideo *video = [[CDVideo alloc] initWithVideoURLPath:@"http://fanhe.dwstatic.com/shortvideo/02/201610/001/3d93b82ee09bee57dc6cd371d4710000.mp4"];
    video.md5 = @"2a46522299b703f52fda40fa1d97691c";
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    while (true) {
        if (CDVideoDownloadStateFinished == task.state) {
            break;
        }
    }
    
    XCTAssert([video.md5 isEqualToString:task.videoFileMD5]);
    
}

//- (void)testPause {
//    CDVideo *video = [[CDVideo alloc] init];
//    video.videoURLPath = self.videoPaths.firstObject;
//
//    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
//    [self.manager addTask:task];
//    [self.manager tryToStartTask:task];
//
//    while (true) {
//        if (CDVideoDownloadStateLoading == task.state) {
//            [task pause];
//            break;
//        }
//
//    }
//
//    XCTAssert(CDVideoDownloadStatePause == task.state);
//
//
//}

- (void)testYield {
    [self.manager pauseAllLoadingTasks];
    
    CDVideo *video = [[CDVideo alloc] init];
    video.videoURLPath = self.videoPaths.firstObject;
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    CDVideo *video2 = [[CDVideo alloc] init];
    video2.videoURLPath = self.videoPaths[1];
    
    CDVideoDownloadTask *task2 = [self.manager makeTaskWithInfo:video2];
    [self.manager addTask:task2];
    [self.manager tryToStartTask:task2];
    
    CDVideo *video3 = [[CDVideo alloc] init];
    video3.videoURLPath = self.videoPaths[2];
    
    CDVideoDownloadTask *task3 = [self.manager makeTaskWithInfo:video3];
    [self.manager addTask:task3];
    [self.manager tryToStartTask:task3];
    
    CDVideo *video4 = [[CDVideo alloc] init];
    video4.videoURLPath = self.videoPaths[3];
    
    CDVideoDownloadTask *task4 = [self.manager makeTaskWithInfo:video4];
    [self.manager addTask:task4];
    [self.manager tryToStartTask:task4];
    
    
    
    XCTAssert(CDVideoDownloadStateWaiting == task4.state);
}

- (void)testDestroy {
    CDVideo *video = [[CDVideo alloc] init];
    video.videoURLPath = self.videoPaths.firstObject;
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    [task destroy];
    
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:task.completeLocalPath]);
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:[NSString toAbsolute:task.taskURLPath]]);
    
}

- (void)testSeperatedArea {
    CDVideoDownloadManager *manager = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:@"testSeperatedArea" class:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"test seperated area"];
    
    CDVideo *video = [[CDVideo alloc] initWithVideoURLPath:self.videoPaths.firstObject];
    CDVideoDownloadTask *task = [manager makeTaskWithInfo:video];
    task.handleDownloadProgress = ^(CGFloat progress) {
        NSLog(@"pppppppp  %f", progress);
        static BOOL ful = NO;
        if (progress >= 0.2 && !ful) {
            ful = YES;
            [expectation fulfill];
        }
    };
    
    [manager addTask:task];
    [manager tryToStartTask:task];
    
    
    [self waitForExpectationsWithTimeout:3600 handler:nil];
    [task pushOffset:(long long)task.totalBytes * 0.9];
    
    
    while (true) {
        if (CDVideoDownloadStateLoaded == task.state) {
            break;
        }
    }
    
    XCTAssert(task.progress <= 0.35);
    
}

//- (void)testAvailable {
//    CDVideoDownloadManager *manager = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:@"testAvailable" class:nil];
//
//    for (NSInteger i=0; i<10; i++) {
//        CDVideo *video = [[CDVideo alloc] initWithVideoURLPath:self.videoPaths[i]];
//
//        CDVideoDownloadTask *task = [manager makeTaskWithInfo:video];
//        task.label = [NSString stringWithFormat:@"tttttt%ld", i];
//        [manager addTask:task];
//        [manager tryToStartTask:task];
//
//    }
//
//    XCTestExpectation *expectation = [self expectationWithDescription:@"test available"];
//    manager.allTasksDidStopped = ^{
//        [expectation fulfill];
//    };
//
//
//    [self waitForExpectationsWithTimeout:180 handler:nil];
//
//    NSInteger success_count = 0;
//    NSInteger error_count = 0;
//
//    for (NSInteger i=0; i<manager.allTasks.count; i++) {
//        CDVideoDownloadTask *task = manager.allTasks[i];
//        if (CDVideoDownloadStateFinished == task.state) {
//            success_count++;
//        }
//
//        if (CDVideoDownloadStateError == task.state) {
//            error_count++;
//        }
//        NSLog(@"iiiiiiiii  %@, sssssssssss  %ld", task.label, task.state);
//
//    }
//
//    NSLog(@"success count %ld", success_count);
//    NSLog(@"error count %ld", error_count);
//
//    XCTAssert(success_count>=10);
//}



@end
