//
//  CDVideoDownloadMegaManager.h
//  CDPlayer
//
//  Created by carusd on 2016/12/7.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDDownloadProtocol.h"


extern NSString * const CDVideoDownloadDirURLDidChanged;

@interface CDVideoDownloadMegaManager : NSObject<CDVideoDownloadTaskPersistenceManager>

+ (instancetype)sharedInstance;

@property (nonatomic, strong) NSURL *cacheDirURL;


- (id<CDVideoDownloadTaskDispatcher>)dispatcherWithTag:(NSString *)tag class:(Class)clazz;
- (NSMutableArray<CDVideoDownloadTask *> *)tasksWithTag:(NSString *)tag;


@end
