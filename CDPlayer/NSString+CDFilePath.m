//
//  NSString+FilePath.m
//  AFNetworking
//
//  Created by carusd on 2017/11/9.
//

#import "NSString+CDFilePath.h"

@implementation NSString (CDFilePath)

+ (NSString *)toAbsolute:(NSString *)relativePath {
    NSString *prefix = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [NSString stringWithFormat:@"%@/%@", prefix, relativePath];
}

+ (void)ensureDirExsit:(NSString *)path {
    BOOL isDir;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    } else {
        if (!isDir) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
}

@end
