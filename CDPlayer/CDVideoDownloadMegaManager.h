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

@property (nonatomic, strong) NSString *cacheDirURLPath; // 在Caches目录下的相对路径


- (id<CDVideoDownloadTaskDispatcher>)dispatcherWithTag:(NSString *)tag class:(Class)clazz;
- (NSMutableArray<CDVideoDownloadTask *> *)tasksWithTag:(NSString *)tag;


@end
