//
//  ViewController.m
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
    
    
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_queue_create("xxxx", DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_group_async(group, queue, ^{
        NSLog(@"group thread = %@ ", [NSThread currentThread]);
        sleep(1);
    });
    
    dispatch_group_async(group, queue, ^{
        NSLog(@"group thread = %@", [NSThread currentThread]);
        sleep(2);
        NSLog(@"sleep ");
    });
    
    dispatch_group_notify(group, queue, ^{
        NSLog(@"do next step");
    });
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
