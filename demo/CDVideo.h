//
//  CDVideo.h
//  CDPlayer
//
//  Created by carusd on 2016/12/13.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDPlayerKit.h"

@interface CDVideo : NSObject<CDVideoInfoProvider>

@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, strong) NSURL *localURL;
@property (nonatomic) NSInteger duration; // 单位为秒
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL completelyLoaded;
@property (nonatomic) int64_t size; // 单位为byte

- (id)initWithPath:(NSString *)path;

@end
