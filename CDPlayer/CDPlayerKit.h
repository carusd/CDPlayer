//
//  CDPlayerKit.h
//  CDPlayer
//
//  Created by carusd on 2016/12/8.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "CDDownloadProtocol.h"
#import "CDVideoBlock.h"
#import "CDVideoDownloadManager.h"
#import "CDVideoDownloadMegaManager.h"
#import "CDVideoDownloadTask.h"
#import "CDPlayer.h"


#ifdef CDPlayerKit_Debug
#define NSLog(log, ...) (NSLog(log, ##__VA_ARGS__))
#else
#define NSLog(log, ...)
#endif
