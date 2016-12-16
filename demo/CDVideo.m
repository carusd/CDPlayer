//
//  CDVideo.m
//  CDPlayer
//
//  Created by carusd on 2016/12/13.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "CDVideo.h"

@implementation CDVideo

- (id)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        self.videoURL = [NSURL URLWithString:path];
        
        NSString *localPath = [NSString stringWithFormat:@"%@%@", NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject, path.lastPathComponent];
        self.localURL = [NSURL fileURLWithPath:localPath];
    }
    
    return self;
}

@end
