//
//  CDVideoBlock.h
//  CDPlayer
//
//  Created by carusd on 2016/12/8.
//  Copyright © 2016年 carusd. All rights reserved.
//

#ifndef CDVideoBlock_h
#define CDVideoBlock_h

@interface CDVideoNormalizedBlock : NSObject

@property double offset;
@property double length;

@end



@interface CDVideoBlock : NSObject<NSCoding>

@property (nonatomic) long long offset;
@property (nonatomic) long long length;

- (id)initWithOffset:(long long)offset length:(long long)length;

- (BOOL)isValid;
- (BOOL)isBlockEqual:(CDVideoBlock *)b;
- (BOOL)containsBlock:(CDVideoBlock *)b;
- (BOOL)containsPosition:(long long)position;
- (BOOL)intersetWithBlock:(CDVideoBlock *)b;
- (CDVideoBlock *)blockWithMergingBlock:(CDVideoBlock *)b;
- (BOOL)between:(CDVideoBlock *)b1 and:(CDVideoBlock *)b2;
@end




#endif /* CDVideoBlock_h */
