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

@property (nonatomic, strong) NSString *videoURLPath;

@property (nonatomic) int64_t duration; // 单位为秒
@property (nonatomic, copy) NSString *title;
@property (nonatomic) int64_t size; // 单位为byte
@property (nonatomic) int64_t width;
@property (nonatomic) int64_t height;
@property (nonatomic, copy) NSString *md5;
@property (readonly) BOOL completelyLoaded;

- (id)initWithVideoURLPath:(NSString *)path;

@end
