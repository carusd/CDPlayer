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
    
    CDVideo *video = [[CDVideo alloc] initWithPath:self.videoPaths.firstObject];
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    while (true) {
        if (CDVideoDownloadStateFinished == task.state) {
            break;
        }
    }
}

- (void)testPause {
    CDVideo *video = [[CDVideo alloc] initWithPath:@"http://funbox.w2.dwstatic.com/52/12/1650/3511348-99-1481592579.mp4"];
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    while (true) {
        if (CDVideoDownloadStateLoading == task.state) {
            [task pause];
            break;
        }
        
    }
    
    XCTAssert(CDVideoDownloadStatePause == task.state);
    
    
}

- (void)testYield {
    [self.manager pauseAllLoadingTasks];
    
    CDVideo *video = [[CDVideo alloc] initWithPath:@"http://funbox.w2.dwstatic.com/52/12/1650/3511348-99-1481592579.mp4"];
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    CDVideo *video2 = [[CDVideo alloc] initWithPath:@"http://funbox.w2.dwstatic.com/57/11/1649/3509634-99-1481260615.mp4"];
    
    CDVideoDownloadTask *task2 = [self.manager makeTaskWithInfo:video2];
    [self.manager addTask:task2];
    [self.manager tryToStartTask:task2];
    
    CDVideo *video3 = [[CDVideo alloc] initWithPath:@"http://funbox.w5.dwstatic.com/59/8/1649/3507589-99-1480989837.mp4"];
    
    CDVideoDownloadTask *task3 = [self.manager makeTaskWithInfo:video3];
    [self.manager addTask:task3];
    [self.manager tryToStartTask:task3];
    
    CDVideo *video4 = [[CDVideo alloc] initWithPath:@"http://funbox.w2.dwstatic.com/55/11/1648/3505854-99-1480644653.mp4"];
    
    CDVideoDownloadTask *task4 = [self.manager makeTaskWithInfo:video4];
    [self.manager addTask:task4];
    [self.manager tryToStartTask:task4];
    
    
    
    XCTAssert(CDVideoDownloadStateWaiting == task4.state);
}

- (void)testDestroy {
    CDVideo *video = [[CDVideo alloc] initWithPath:self.videoPaths.firstObject];
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    [task destroy];
    
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:task.videoURL.absoluteString]);
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:task.taskURL.absoluteString]);
    
}

- (void)testSeperatedArea {
    CDVideoDownloadManager *manager = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:@"testSeperatedArea" class:nil];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"test seperated area"];
    
    CDVideo *video = [[CDVideo alloc] initWithPath:@"http://funbox.w2.dwstatic.com/52/12/1650/3511348-99-1481592579.mp4"];
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
    
    task.offset = (long long)task.totalBytes * 0.9;
    
    while (true) {
        if (CDVideoDownloadStateLoaded == task.state) {
            break;
        }
    }
    
    XCTAssert(task.progress <= 0.35);
    
}

- (void)testAvailable {
    CDVideoDownloadManager *manager = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:@"testAvailable" class:nil];
    
    for (NSInteger i=0; i<100; i++) {
        CDVideo *video = [[CDVideo alloc] initWithPath:self.videoPaths[i]];
        
        CDVideoDownloadTask *task = [manager makeTaskWithInfo:video];
        task.label = [NSString stringWithFormat:@"tttttt%ld", i];
        [manager addTask:task];
        [manager tryToStartTask:task];
        
    }
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"test available"];
    manager.allTasksDidStopped = ^{
        [expectation fulfill];
    };
    

    [self waitForExpectationsWithTimeout:1600 handler:nil];
    
    NSInteger success_count = 0;
    NSInteger error_count = 0;
    
    for (NSInteger i=0; i<manager.allTasks.count; i++) {
        CDVideoDownloadTask *task = manager.allTasks[i];
        if (CDVideoDownloadStateFinished == task.state) {
            success_count++;
        }
        
        if (CDVideoDownloadStateLoadError == task.state) {
            error_count++;
        }
        NSLog(@"iiiiiiiii  %@, sssssssssss  %ld", task.label, task.state);
        
    }
    
    NSLog(@"success count %ld", success_count);
    NSLog(@"error count %ld", error_count);
    
}



@end
