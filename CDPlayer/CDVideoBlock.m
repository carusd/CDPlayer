//
//  CDVideoBlock.m
//  CDPlayer
//
//  Created by carusd on 2016/12/8.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDVideoBlock.h"


@implementation CDVideoBlock

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        self.offset = [aDecoder decodeInt64ForKey:@"offset"];
        self.length = [aDecoder decodeInt64ForKey:@"length"];
        
    }
    
    return self;
    
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeInt64:self.offset forKey:@"offset"];
    [aCoder encodeInt64:self.length forKey:@"length"];
}

- (id)initWithOffset:(long long)offset length:(long long)length {
    self = [super init];
    if (self) {
        self.offset = offset;
        self.length = length;
    }
    
    return self;
}

- (BOOL)isValid {
    return self.offset >= 0 && self.length > 0;
}

- (BOOL)isBlockEqual:(CDVideoBlock *)b {
    return (self.offset == b.offset && self.length == b.length);
}

- (BOOL)containsBlock:(CDVideoBlock *)b {
    return (self.offset <= b.offset && self.offset + self.length >= b.offset + b.length);
}

- (BOOL)intersetWithBlock:(CDVideoBlock *)b {
    if (self.offset == b.offset) {
        return YES;
    } else if (self.offset > b.offset) {
        if (b.offset + b.length >= self.offset) {
            return YES;
        } else {
            return NO;
        }
    } else {
        if (self.offset + self.length >= b.offset) {
            return YES;
        } else {
            return NO;
        }
    }
}

- (CDVideoBlock *)blockWithMergingBlock:(CDVideoBlock *)b {
    CDVideoBlock * result = [[CDVideoBlock alloc] init];
    
    if ([self intersetWithBlock:b]) {
        if (self.offset == b.offset) {
            result.length = MAX(self.length, b.length);
        } else if (self.offset > b.offset) {
            result.offset = b.offset;
            result.length = self.offset - b.offset + self.length;
        } else {
            result.offset = self.offset;
            result.length = b.offset - self.offset + b.length;
        }
    }
    
    return result;
}

- (BOOL)between:(CDVideoBlock *)b1 and:(CDVideoBlock *)b2 {
    return (self.offset > b1.offset + b1.length && self.offset + self.length < b2.offset);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"offset: %lld, length: %lld", self.offset, self.length];
}

@end

