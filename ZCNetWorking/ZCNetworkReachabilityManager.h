//
//  ZCNetworkReachabilityManager.h
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import <Foundation/Foundation.h>

#if  !TARGET_OS_WATCH
#import <SystemConfiguration/SystemConfiguration.h>

typedef NS_ENUM(NSInteger, ZCNetworkingReachabilityStatus){
    ZCNetworkingReachabilityStatusUnkonwn          = -1,
    ZCNetworkingReachabilityStatusNotReachable     = 0,
    ZCNetworkingReachabilityStatusReachableViaWWAN = 1,
    ZCNetworkingReachabilityStatusReachableViaWiFi = 2,
};


NS_ASSUME_NONNULL_BEGIN

@interface ZCNetworkReachabilityManager : NSObject

@property (readonly, nonatomic, assign) ZCNetworkingReachabilityStatus networkReachabilityStatus;

@property (readonly, nonatomic, assign, getter = isReachable) BOOL reachable;

@property (readonly, nonatomic, assign, getter = isReachableViaWWAN) BOOL reachableViaWWAN;

@property (readonly, nonatomic, assign, getter = isReachabilityViaWiFi) BOOL reachabilityViaWiFi;



+ (instancetype)sharedManager;

+ (instancetype)manager;

+ (instancetype)managerForDomain:(NSString *)domain;

+ (instancetype)managerForAddress:(const void *)address;

//NS_DESIGNATED_INITIALIZER Objective-C 中主要通过NS_DESIGNATED_INITIALIZER宏来实现指定构造器的。这里之所以要用这个宏，往往是想告诉调用者要用这个方法去初始化（构造）类对象。
- (instancetype)initWithReability:(SCNetworkReachabilityRef)reachability NS_DESIGNATED_INITIALIZER;
//NS_UNAVAILABLE 不希望调用者使用init方法初始化
- (nullable instancetype)init NS_UNAVAILABLE;

- (void)startMonitoring;

- (void)stopMonitoring;

/**
    @name Getting Localied Reachbility Description
 */
- (NSString *)localizedNetworkReachabilityStatusString;
@end

FOUNDATION_EXPORT NSString * const ZCNetworkingReachabilityDidChangeNotification;
FOUNDATION_EXPORT NSString *const ZCNetworkingReachabilityNotificationStatusItem;

FOUNDATION_EXPORT NSString * const ZCStringFromNetworkReachabilityStatus(ZCNetworkingReachabilityStatus status);

NS_ASSUME_NONNULL_END

#endif
