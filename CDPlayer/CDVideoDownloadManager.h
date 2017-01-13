//
//  CDVideoDownloadManager.h
//  CDPlayer
//
//  Created by carusd on 2016/11/29.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDDownloadProtocol.h"

typedef void(^AllTasksDidStopped)(void);

@interface CDVideoDownloadManager : NSObject<CDVideoDownloadTaskDispatcher> {
    
    NSMutableArray<CDVideoDownloadTask *> *_tasks;
}

@property (nonatomic, copy) AllTasksDidStopped allTasksDidStopped;



- (void)launchLoading;

@end
