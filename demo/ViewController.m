//
//  ViewController.m
//  CDPlayer
//
//  Created by carusd on 2016/11/25.
//  Copyright © 2016年 carusd. All rights reserved.
//

#import "ViewController.h"
#import "CDPlayerKit.h"
#import "CDVideo.h"
#import "AFNetworking.h"

@interface ViewController ()

@property (nonatomic, strong) CDVideoDownloadManager *manager;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    CDVideo *video = [[CDVideo alloc] initWithVideoURLPath:@"http://fanhe.dwstatic.com/shortvideo/02/201610/001/3d93b82d668cee57e5104f8950890000.mp4"];
    
    self.manager = [[CDVideoDownloadMegaManager sharedInstance] dispatcherWithTag:@"viewController" class:nil];
    
    CDVideoDownloadTask *task = [self.manager makeTaskWithInfo:video];
    [self.manager addTask:task];
    [self.manager tryToStartTask:task];
    
    
    [[AFHTTPSessionManager manager] GET:@"http://www.baidu.com" parameters:nil progress:nil success:nil failure:nil];
}



@end
