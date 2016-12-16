//
//  CDVideoBlock.h
//  CDPlayer
//
//  Created by carusd on 2016/12/8.
//  Copyright © 2016年 carusd. All rights reserved.
//

#ifndef CDVideoBlock_h
#define CDVideoBlock_h


typedef struct
{
    long long offset;
    long long length;
} CDVideoBlock;

extern const CDVideoBlock CDVideoBlockZero;

extern CDVideoBlock CDVideoBlockMake(long long offset, long long length);
extern BOOL CDVideoBlockEqual(CDVideoBlock b1, CDVideoBlock b2);
extern BOOL CDVideoBlockContainsBlock(CDVideoBlock b1, CDVideoBlock b2);
extern BOOL CDVideoBlockIntersect(CDVideoBlock b1, CDVideoBlock b2);
extern CDVideoBlock CDVideoBlockMerge(CDVideoBlock b1, CDVideoBlock b2);
extern BOOL CDVideoBlockBetween(CDVideoBlock b1, CDVideoBlock b2, CDVideoBlock b3);


#endif /* CDVideoBlock_h */
