//
//  CDVideo.m
//  CDPlayer
//
//  Created by carusd on 2016/12/13.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "CDVideo.h"
#import "NSString+CDFilePath.h"
@interface CDVideo() {
    NSString *_localURLPath;
}

@end

@implementation CDVideo
@synthesize localURLPath = _localURLPath;

- (id)initWithVideoURLPath:(NSString *)path {
    self = [super init];
    if (self){
        self.videoURLPath = path;
    }
    return self;
}


- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        self.videoURLPath = [aDecoder decodeObjectForKey:@"videoURLPath"];
        
        self.duration = [aDecoder decodeInt64ForKey:@"duration"];
        self.width = [aDecoder decodeInt64ForKey:@"width"];
        self.height = [aDecoder decodeInt64ForKey:@"height"];
        
        self.size = [aDecoder decodeInt64ForKey:@"size"];
        self.md5 = [aDecoder decodeObjectForKey:@"md5"];
        self.title = [aDecoder decodeObjectForKey:@"title"];
        
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.videoURLPath forKey:@"videoURLPath"];
    
    [aCoder encodeObject:self.md5 forKey:@"md5"];
    [aCoder encodeObject:self.title forKey:@"title"];
    [aCoder encodeInt64:self.duration forKey:@"duration"];
    [aCoder encodeInt64:self.size forKey:@"size"];
    [aCoder encodeInt64:self.width forKey:@"width"];
    [aCoder encodeInt64:self.height forKey:@"height"];
}

- (void)setVideoURLPath:(NSString *)videoURLPath {
    _videoURLPath = videoURLPath;
    
    NSString *filename = [videoURLPath lastPathComponent];
    _localURLPath = [NSString stringWithFormat:@"%@/%@", [CDVideoDownloadMegaManager sharedInstance].videoDirName, filename];
}

- (NSString *)completeLocalPath {
    return [NSString toAbsolute:_localURLPath];
}

- (BOOL)completelyLoaded {
    
    CDVideoDownloadTask *task = [[CDVideoDownloadMegaManager sharedInstance] taskWithInfo:self];
    if (task.state != CDVideoDownloadStateFinished) {
        return NO;
    } else {
        if (self.md5.length > 0) {
            if ([self.md5 isEqualToString:task.videoFileMD5]) {
                return YES;
            } else {
                return NO;
            }
        } else {
            return YES;
        }
        
    }
}

- (CGFloat)ratio {
    if (self.height > 0) {
        return (self.width * 1.0) / self.height;
    } else {
        return 0;
    }
}


- (NSString *)description {
    return [NSString stringWithFormat:@"title: %@, video url: %@", self.title, self.videoURLPath];
}


@end
