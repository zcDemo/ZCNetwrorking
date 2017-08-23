//
//  ZCNetworkReachabilityManager.m
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import "ZCNetworkReachabilityManager.h"
#if !TARGET_OS_WATCH

#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

NSString * const ZCNetworkingReachabilityDidChangeNotification = @"com.zcnetworking.reachability.change";
NSString * const ZCNetworkingReachabilityNotificationStatusItem = @"com.zcnetworking.reachability.statusItem";

typedef void (^ZCNetworkingReachabilityStatusBlock)(ZCNetworkingReachabilityStatus status);

NSString * ZCStringFromNetworkReachabilityStatus(ZCNetworkingReachabilityStatus status){
    switch (status) {
        case ZCNetworkingReachabilityStatusNotReachable:
            return NSLocalizedStringFromTable(@"Not Reachable", @"ZCNetworking", nil);
        case ZCNetworkingReachabilityStatusReachableViaWWAN:
            return NSLocalizedStringFromTable(@"Reachable via WWAN", @"ZCNetworking", nil);
        case ZCNetworkingReachabilityStatusReachableViaWiFi:
            return NSLocalizedStringFromTable(@"Reachable via WiFi", @"ZCNetworking", nil);
        case ZCNetworkingReachabilityStatusUnkonwn:
        default:
            return NSLocalizedStringFromTable(@"Unknow", @"ZCNetworking", nil);
    }
}

static ZCNetworkingReachabilityStatus ZCNetworkingReachabilityStatusForFlags(SCNetworkConnectionFlags flags){
    BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
    BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
    BOOL canConnectionAutomatically = (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand) != 0) || ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0));
    BOOL canConnectWithoutUserInteraction = (canConnectionAutomatically && (flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0);
    BOOL isNetworkReachable = (isReachable && (!needsConnection || canConnectWithoutUserInteraction));
    
    ZCNetworkingReachabilityStatus status = ZCNetworkingReachabilityStatusUnkonwn;
    if (isNetworkReachable == NO) {
        status = ZCNetworkingReachabilityStatusNotReachable;
    } else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0){
        status = ZCNetworkingReachabilityStatusReachableViaWWAN;
    } else{
        status = ZCNetworkingReachabilityStatusReachableViaWiFi;
    }
    
    return status;
}


static void ZCPostReachabilityStatusChange(SCNetworkConnectionFlags flags, ZCNetworkingReachabilityStatusBlock block){
    ZCNetworkingReachabilityStatus status = ZCNetworkingReachabilityStatusForFlags(flags);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (block) {
            block(status);
        }
        
        NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
        NSDictionary *userInfo = @{ZCNetworkingReachabilityNotificationStatusItem:@(status)};
        [notificationCenter postNotificationName:ZCNetworkingReachabilityDidChangeNotification object:nil userInfo:userInfo];
    });
}

static void ZCNetworkingReachabilityCallback(SCNetworkReachabilityRef __unused target, SCNetworkConnectionFlags flags, void *info){
    ZCPostReachabilityStatusChange(flags, (__bridge ZCNetworkingReachabilityStatusBlock)info);
}

static const void * ZCNetworkReachabilityRetainCallback(const void *info){
    return Block_copy(info);
}

static void ZCNetworkReachabilityReleaseCallback(const void *info){
    if (info) {
        Block_release(info);
    }
}

@interface ZCNetworkReachabilityManager ()
@property (readonly, nonatomic , assign) SCNetworkReachabilityRef networkReachability;
@property (readwrite, nonatomic, assign) ZCNetworkingReachabilityStatus networkReachabilityStatus;
@property (readwrite, nonatomic, copy) ZCNetworkingReachabilityStatusBlock networkReachabilityStatusBlock;
@end

@implementation ZCNetworkReachabilityManager

+ (instancetype)sharedManager{
    static ZCNetworkReachabilityManager *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [self manager];
    });
    
    return _sharedManager;
}

+ (instancetype)managerForDomain:(NSString *)domain{
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [domain UTF8String]);
    
    ZCNetworkReachabilityManager *manager = [[self alloc] initWithReability:reachability];
    
    CFRelease(reachability);
    
    return manager;
}

+ (instancetype)managerForAddress:(const void *)address{
    SCNetworkReachabilityRef reachability  = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)address);
    ZCNetworkReachabilityManager *manager = [[self alloc] initWithReability:reachability];
    
    CFRelease(reachability);
    
    return manager;
}

+ (instancetype)manager{
#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 90000) || (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED >= 101100)
    struct sockaddr_in6 address;
    bzero(&address, sizeof(address));
    address.sin6_len = sizeof(address);
    address.sin6_family = AF_INET;
#else
    struct sockaddr_in address;
    bzero(&address, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
#endif
    return [self managerForAddress:&address];
}

- (instancetype)initWithReability:(SCNetworkReachabilityRef)reachability{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _networkReachability = CFRetain(reachability);
    self.networkReachabilityStatus = ZCNetworkingReachabilityStatusUnkonwn;
    
    return self;
}

- (instancetype)init NS_UNAVAILABLE{
    return nil;
}

- (void)dealloc{
    [self stopMonitoring];
    
    if (_networkReachability != NULL) {
        CFRelease(_networkReachability);
    }
}

#pragma mark - 

- (BOOL)isReachable{
    return [self isReachableViaWWAN] || [self isReachabilityViaWiFi];
}

- (BOOL)isReachableViaWWAN{
    return self.networkReachabilityStatus == ZCNetworkingReachabilityStatusReachableViaWWAN;
}

- (BOOL)isReachabilityViaWiFi{
    return self.networkReachabilityStatus == ZCNetworkingReachabilityStatusReachableViaWiFi;
}

#pragma mark -

- (void)startMonitoring{
    [self stopMonitoring];
    
    if (!self.networkReachability) {
        return;
    }
    
    __weak __typeof(self)weakSelf = self;
    ZCNetworkingReachabilityStatusBlock callback = ^(ZCNetworkingReachabilityStatus status){
        __strong __typeof(self)strongSelf = weakSelf;
        
        strongSelf.networkReachabilityStatus = status;
        if (strongSelf.networkReachabilityStatusBlock) {
            strongSelf.networkReachabilityStatusBlock(status);
        }
    };
    
    SCNetworkReachabilityContext context = {0, (__bridge void *)callback, ZCNetworkReachabilityRetainCallback, ZCNetworkReachabilityReleaseCallback, NULL};
    SCNetworkReachabilitySetCallback(self.networkReachability, ZCNetworkingReachabilityCallback, &context);
    SCNetworkReachabilityScheduleWithRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags(self.networkReachability, &flags)) {
            ZCPostReachabilityStatusChange(flags, callback);
        }
    });
}

- (void)stopMonitoring{
    if (!self.networkReachability) {
        return;
    }
    
    SCNetworkReachabilityUnscheduleFromRunLoop(self.networkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
}

#pragma mark - 

- (NSString *)localizedNetworkReachabilityStatusString{
    return ZCStringFromNetworkReachabilityStatus(self.networkReachabilityStatus);
}

#pragma mark - 

- (void)setReachabilityStatusChangeBlock:(void (^)(ZCNetworkingReachabilityStatus status))block{
    self.networkReachabilityStatusBlock = block;
}

#pragma mark - NSKeyValueObserving

+ (NSSet<NSString *> *)keyPathsForValuesAffectingValueForKey:(NSString *)key{
    if ([key isEqualToString:@"reachable"] || [key isEqualToString:@"reachableViaWWAN"] || [key isEqualToString:@"reachableViaWiFi"]) {
        return [NSSet setWithObject:@"networkReachabilityStatus"];
    }
    
    return [super keyPathsForValuesAffectingValueForKey:key];
}

@end
#endif
