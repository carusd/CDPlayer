//
//  NSString+FilePath.h
//  AFNetworking
//
//  Created by carusd on 2017/11/9.
//

#import <Foundation/Foundation.h>

@interface NSString (CDFilePath)

+ (NSString *)toAbsolute:(NSString *)relativePath;
+ (void)ensureDirExsit:(NSString *)path;

@end
