//
//  AppDelegate.m
//  CDPlayer
//
//  Created by carusd on 2016/11/25.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "AppDelegate.h"
#import "CDPlayer.h"
#import "AFNetworking.h"

@interface AppDelegate ()

@property (nonatomic, strong) CDVideoDownloadTask *task;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}

@end
