//
//  CDVideoBlock.m
//  CDPlayer
//
//  Created by carusd on 2016/12/8.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CDVideoBlock.h"



const CDVideoBlock CDVideoBlockZero = {0, 0};

inline CDVideoBlock CDVideoBlockMake(long long offset, long long length) {
    CDVideoBlock block = {offset, length};
    return block;
}

inline BOOL CDVideoBlockEqual(CDVideoBlock b1, CDVideoBlock b2) {
    return (b1.offset == b2.offset && b1.length == b2.length);
}

inline BOOL CDVideoBlockContainsBlock(CDVideoBlock b1, CDVideoBlock b2) {
    return (b1.offset <= b2.offset && b1.offset + b1.length >= b2.offset + b2.length);
}

inline BOOL CDVideoBlockIntersect(CDVideoBlock b1, CDVideoBlock b2) {
    if (b1.offset == b2.offset) {
        return YES;
    } else if (b1.offset > b2.offset) {
        if (b2.offset + b2.length >= b1.offset) {
            return YES;
        } else {
            return NO;
        }
    } else {
        if (b1.offset + b1.length >= b2.offset) {
            return YES;
        } else {
            return NO;
        }
    }
}

inline CDVideoBlock CDVideoBlockMerge(CDVideoBlock b1, CDVideoBlock b2) {
    CDVideoBlock result = {0, 0};
    
    if (CDVideoBlockIntersect(b1, b2)) {
        if (b1.offset == b2.offset) {
            result.length = MAX(b1.length, b2.length);
        } else if (b1.offset > b2.offset) {
            result.offset = b2.offset;
            result.length = b1.offset - b2.offset + b1.length;
        } else {
            result.offset = b1.offset;
            result.length = b2.offset - b1.offset + b2.length;
        }
    }
    
    return result;
}

inline BOOL CDVideoBlockBetween(CDVideoBlock b1, CDVideoBlock b2, CDVideoBlock b3) {
    return (b2.offset > b1.offset + b1.length && b2.offset + b2.length < b3.offset);
}
