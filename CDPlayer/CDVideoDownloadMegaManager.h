//
//  CDVideoDownloadMegaManager.h
//  CDPlayer
//
//  Created by carusd on 2016/12/7.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDDownloadProtocol.h"




@interface CDVideoDownloadMegaManager : NSObject<CDVideoDownloadTaskPersistenceManager>

+ (instancetype)sharedInstance;

// 设置目录名即可，megaManager会自动创建
@property (nonatomic, strong) NSString *taskDirName; // 在Caches目录下存放task的目录名
@property (nonatomic, strong) NSString *videoDirName; // 在Caches目录下存放video的目录名

- (id<CDVideoDownloadTaskDispatcher>)dispatcherWithTag:(NSString *)tag class:(Class)clazz;
- (NSMutableArray<CDVideoDownloadTask *> *)tasksWithTag:(NSString *)tag;

- (CDVideoDownloadTask *)taskWithInfo:(id<CDVideoInfoProvider>)infoProvider;
@end
