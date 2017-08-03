//
//  ZCURLSessionManager.m
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import "ZCURLSessionManager.h"
#import <objc/runtime.h>

#ifndef NSFoundationVersionNumber_iOS_8_0
#define NSFoundationVersionNumber_With_Fixed_5871104061079552_bug 
        1140.11
#else
#define NSFoundationVersionNumber_With_Fixed_5871104061079552_bug NSFoundationVersionNumber_iOS_8_0
#endif

static dispatch_queue_t url_session_manageer_creation_queue() {
    static dispatch_queue_t zc_url_session_manager_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zc_url_session_manager_creation_queue = dispatch_queue_create("com.zc.networking.session.manager.create", DISPATCH_QUEUE_SERIAL);
    });
    return zc_url_session_manager_creation_queue;
}

static void url_session_manager_create_task_safely(dispatch_block_t block){
    if (NSFoundationVersionNumber < NSFoundationVersionNumber_With_Fixed_5871104061079552_bug) {
        dispatch_sync(url_session_manageer_creation_queue(), block);
    } else {
        block();
    }
}

static dispatch_queue_t url_session_manager_processsing_queue() {
    static dispatch_queue_t zc_url_session_manager_processing_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zc_url_session_manager_processing_queue = dispatch_queue_create("com.zc.networking.session.manager.processing", DISPATCH_QUEUE_CONCURRENT);
    });
    
    return zc_url_session_manager_processing_queue;
}

static dispatch_group_t url_session_manager_completion_group() {
    static dispatch_group_t zc_url_session_manger_completion_group;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zc_url_session_manger_completion_group = dispatch_group_create();
    });
    
    return zc_url_session_manger_completion_group;
}

NSString * const ZCNetworkingTaskDidResumeNotificaiton = @"com.zc.networking.task.resume";
NSString * const ZCNetworkingTaskDidCompleteNotification = @"com.zc.networking.task.complete";
NSString * const ZCNetworkingTaskDidSuspendNotifiacition = @"com.zc.networking.suspend";
NSString * const ZCURLSessionDidInvalidateNotificaiton = @"com.zc.networking.session.invalidate";
NSString * const ZCURLSessioDownloadTaskDidFailToMoveFileNotification = @"com.zc.networking.session.download.file_mamager_error";

NSString * const ZCNetworkingTaskDidCompleteResponseDataKey = @"com.zc.networking.task.complete.response.d";
NSString * const ZCNetworkingTaskDidCompleteSerializedResponseKey = @"com.zc.networking.task.complete.serializedresponse";
NSString * const ZCNetworkingTaskDidCompleteResponseSerializerKey = @"com.zc.networking.task.complete.responseserializer";
NSString * const ZCNetworkingTaskDidCompleteAssetPathKey = @"com.zc.networking.task.complete.assetpath";
NSString * const  ZCNetWorkingTaskDidCompleteErrorKey = @"com.zc.networking.task.complete.error";

static NSString * const ZCURLSessionMangerLockName = @"com.zc.networking.task.session.manager.lock";

static NSUInteger const ZCMaximumNumberOfAttemptsToRecreateBackgorundSessionUploadTask = 3;

typedef void (^ZCURLSessionDidBecomeInvalidBlock)(NSURLSession *session, NSError *error);
typedef NSURLSessionAuthChallengeDisposition (^ZCURLSessionDidReceiveAuthenticationChallengeBlock)(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential);

typedef NSURLRequest * (^ZCURLSessionTaskWillPerformHTTPRedirectionBlock)(NSURLSession *session, NSURLSessionTask *task, NSURLResponse *response, NSURLRequest *request);
typedef NSURLSessionAuthChallengeDisposition (^ZCURLSessionTaskDidReceiveAuthenticationChallengeBlock)(NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, NSURLCredential * __autoreleasing *credential);

typedef void (^ZCURLSessionDidFinishEventsForBackgroundURLSessionBlock)(NSURLSession *session);

typedef NSInputStream * (^ZCURLSessionTaskNeedNewBodyStreamBlock)(NSURLSession *session, NSURLSessionTask *task);
typedef  void (^ZCURLSessionTaskDidSendBodyDataBlock)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend);
typedef void (^ZCURLSessionTaskDidCompleteBlock)(NSURLSession *session, NSURLSessionTask *task, NSError *error);

typedef NSURLSessionResponseDisposition (^ZCURLSessionDataTaskDidReceiveResponseBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response);
typedef void(^ZCURLSessionDataTaskDidBecomeDownloadTaskBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask);
typedef void(^ZCURLSessionDataTaskDidReceiveDataBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data);
typedef NSCachedURLResponse * (^ZCURLSessionDataTaskWillCacheResponseBlock)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSCachedURLResponse *proposedResponse);

typedef NSURL * (^ZCURLSessionDownloadTaskDidFinishDownloadBlock) (NSURLSession *session, NSURLSessionDownloadTask *downloadTask, NSURL *locaiotn);
typedef void (^ZCURLSessionDownloadTaskDidWriteDataBlock)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite);
typedef void(^ZCURLSessionDownloadTaskDidResumBlock)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t filOffset, int64_t expectedTotalBytes);
typedef void (^ZCURLSessionTaskProgressBlock)(NSProgress *);

typedef void (^ZCURLSessionTaskCompleteHandler)(NSURLResponse *response, id responseObject, NSError *error);


#pragma mark -

@interface ZCURLSessionManagerTaskDelegate : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>
- (instancetype)initWithTask:(NSURLSessionTask *)task;
@property (nonatomic, weak) ZCURLSessionManager *manager;
@property (nonatomic, strong) NSMutableData *mutableData;
@property (nonatomic, strong) NSProgress *uploadProgress;
@property (nonatomic, strong) NSProgress *downloadPorgress;
@property (nonatomic, copy) NSURL *downloadFileURL;
@property (nonatomic, copy) ZCURLSessionDownloadTaskDidFinishDownloadBlock downloadTaskDidFinishDownloading;
@property (nonatomic, copy) ZCURLSessionTaskProgressBlock uploadProgressBlock;
@property (nonatomic, copy) ZCURLSessionTaskProgressBlock downloadProgressBlock;
@property (nonatomic, copy) ZCURLSessionTaskCompleteHandler completionHandler;
@end

@implementation ZCURLSessionManagerTaskDelegate

- (instancetype)initWithTask:(NSURLSessionTask *)task{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _mutableData = [NSMutableData data];
    _uploadProgress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
    _downloadPorgress = [[NSProgress alloc] initWithParent:nil userInfo:nil];
    
    
    __weak __typeof__(task) weakTask = task;
    for (NSProgress *progress in @[ _uploadProgress, _downloadPorgress]) {
        progress.totalUnitCount = NSURLSessionTransferSizeUnknown;
        progress.cancellable = YES;
        progress.cancellationHandler = ^{
            [weakTask cancel];
        };
        progress.pausable = YES;
        progress.pausingHandler = ^{
            [weakTask suspend];
        };
        if ([progress respondsToSelector:@selector(setResumingHandler:)]) {
            progress.resumingHandler = ^{
                [weakTask resume];
            };
        }
        [progress addObserver:self
                   forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                      options:NSKeyValueObservingOptionNew context:NULL];
    }
    return self;
}

- (void)dealloc{
    [self.uploadProgress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
    [self.downloadPorgress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
}

#pragma mark - NSProgress Tracking

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    if ([object isEqual:self.downloadPorgress]) {
        if (self.downloadProgressBlock) {
            self.downloadProgressBlock(object);
        }
    }
    
    if ([object isEqual:self.uploadProgress]) {
        if (self.uploadProgressBlock) {
            self.uploadProgressBlock(object);
        }
    }
}

#pragma mark - NSURLSessionTaskDelegate
//__unused 定义变量后 如果不适用会出现警告 __unused 会去除这个警告
- (void)URLSession:(__unused NSURLSession *)sessoin task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error{
    __strong ZCURLSessionManager *manager = self.manager;
    
    __block id responseObject = nil;
    
    __block NSMutableDictionary *useInfo = [NSMutableDictionary dictionary];
    useInfo[ZCNetworkingTaskDidCompleteResponseSerializerKey] = manager.responseSerializer;
    
    NSData *data = nil;
    if (self.mutableData) {
        data = [self.mutableData copy];
        self.mutableData = nil;
    }
    
    if (self.downloadFileURL) {
        useInfo[ZCNetworkingTaskDidCompleteAssetPathKey] = self.downloadFileURL;
    } else if (data){
        useInfo[ZCNetworkingTaskDidCompleteResponseDataKey] = data;
    }
    
    if (error) {
        useInfo[ZCNetWorkingTaskDidCompleteErrorKey] = error;
        
        dispatch_group_async(manager.completionGroup ?: url_session_manager_completion_group(), manager.completionQueue, ^{
            if (self.completionHandler) {
                self.completionHandler(task.response, responseObject, error);
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZCNetworkingTaskDidCompleteNotification object:task userInfo:useInfo];
            });
        });
    } else {
        dispatch_async(url_session_manager_processsing_queue(), ^{
            NSError *serializationError = nil;
            responseObject = [manager.responseSerializer responseObjectForResponse:task.response data:data error:&serializationError];
            
            if (self.downloadFileURL) {
                responseObject = self.downloadFileURL;
            }
            
            if (responseObject) {
                useInfo[ZCNetworkingTaskDidCompleteSerializedResponseKey] = responseObject;
            }
            
            if (serializationError) {
                useInfo[ZCNetWorkingTaskDidCompleteErrorKey] = serializationError;
            }
            
            dispatch_group_async(manager.completionGroup ?:url_session_manager_completion_group(), manager.completionQueue ?: dispatch_get_main_queue(), ^{
                if (self.completionHandler) {
                    self.completionHandler(task.response, responseObject, serializationError);
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter] postNotificationName:ZCNetworkingTaskDidCompleteNotification object:task userInfo:useInfo];
                });
            });
        });
    }
}


#pragma  mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data{
    self.downloadPorgress.totalUnitCount = dataTask.countOfBytesExpectedToReceive;
    self.downloadPorgress.completedUnitCount = dataTask.countOfBytesReceived;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend{
    self.uploadProgress.totalUnitCount = task.countOfBytesExpectedToSend;
    self.uploadProgress.completedUnitCount = task.countOfBytesSent;
}

#pragma mark = NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    self.downloadPorgress.totalUnitCount = totalBytesExpectedToWrite;
    self.downloadPorgress.completedUnitCount = totalBytesWritten;
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location{
    self.downloadFileURL = nil;
    
    if (self.downloadTaskDidFinishDownloading) {
        self.downloadTaskDidFinishDownloading(session, downloadTask, location);
        if (self.downloadFileURL) {
            NSError *fileManagerError = nil;
            
            if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:self.downloadFileURL error:&fileManagerError]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:ZCURLSessioDownloadTaskDidFailToMoveFileNotification object:downloadTask userInfo:fileManagerError.userInfo];
            }
        }
    }
    
}

@end

#pragma mark -

//inline  内联函数 有宏定义的功能 
static inline void zc_swizzleSelector(Class theClass, SEL originalSelector, SEL swizzledSelector){
    Method originalMethod = class_getInstanceMethod(theClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(theClass, swizzledSelector);
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

static inline BOOL zc_addMethod(Class theClass, SEL selector, Method method){
    return class_addMethod(theClass, selector, method_getImplementation(method), method_getTypeEncoding(method));
}

static NSString * const ZCRULSessionTaskDidResumeNotification = @"com.zc.networking.nsurlsessiontask.resume";
static NSString * const ZCURLSessonTaskDidSuspendNotification = @"com.zc.networking.nsurlsessiontask.suspend";

@interface _ZCURLSessionTaskSwizzling : NSObject

@end

@implementation _ZCURLSessionTaskSwizzling

+ (void)load{
    if (NSClassFromString(@"NSURLSessionTask")){
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wnonnull"
        NSURLSessionDataTask *localDataTask = [session dataTaskWithURL:nil];
#pragma clang diagnostic pop
        IMP originalZCResumeIMP = method_getImplementation(class_getInstanceMethod([self class], @selector(zc_resume)));
        Class currentClass = [localDataTask class];
        
        while (class_getInstanceMethod(currentClass, @selector(resume))) {
            Class superClass = [currentClass superclass];
            IMP classResumeIMP = method_getImplementation(class_getInstanceMethod(currentClass, @selector(resume)));
            IMP superclassResumeIMP = method_getImplementation(class_getInstanceMethod(superClass, @selector(resume)));
            if (classResumeIMP != superclassResumeIMP && originalZCResumeIMP != classResumeIMP) {
                [self swizzleResumeAndSuspendMethodForClass:currentClass];
            }
            currentClass = [currentClass class];
        }
        
        [localDataTask cancel];
        [session finishTasksAndInvalidate];
    }
}

+ (void)swizzleResumeAndSuspendMethodForClass:(Class)theClass{
    Method zcResumeMethod = class_getInstanceMethod(self, @selector(zc_resume));
    Method zcSuspendMethod = class_getInstanceMethod(self, @selector(zc_suspend));
    
    if (zc_addMethod(theClass, @selector(zc_resume), zcResumeMethod)) {
        zc_swizzleSelector(theClass, @selector(resume), @selector(zc_resume));
    }
    
    if (zc_addMethod(theClass, @selector(zc_suspend), zcSuspendMethod)) {
        zc_swizzleSelector(theClass, @selector(suspend), @selector(zc_suspend));
    }
}

- (NSURLSessionTaskState)state{
    NSAssert(NO, @"state method should never be called in the actual dummy class");
    return NSURLSessionTaskStateCanceling;
}

- (void)zc_resume{
    NSAssert([self respondsToSelector:@selector(state)], @"Does not respond to state");
    NSURLSessionTaskState state = [self state];
    [self zc_resume];
    
    if (state != NSURLSessionTaskStateRunning) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ZCRULSessionTaskDidResumeNotification object:self];
    }
}

- (void)zc_suspend{
    NSAssert([self respondsToSelector:@
              selector(state)], @"Does not respond to state");
    NSURLSessionTaskState state = [self state];
    [self zc_suspend];
    
    if (state != NSURLSessionTaskStateSuspended) {
        [[NSNotificationCenter defaultCenter] postNotificationName:ZCURLSessonTaskDidSuspendNotification object:self];
    }
    
}
@end

#pragma mark -

@interface ZCURLSessionManager ()
@property (readwrite, nonatomic, strong) NSURLSessionConfiguration *sessionConfiguration;
@property (readwrite, nonatomic, strong) NSOperationQueue *operationQueue;
@property (readwrite, nonatomic, strong) NSURLSession *session;
@property (readwrite, nonatomic, strong) NSMutableDictionary *mutableTaskDelegatesKeyedByTaskIndentifier;
@property (readonly, nonatomic, copy)   NSString *taskDescriptionForSessionTask;
@property (readwrite, nonatomic, strong) NSLock *lock;
@property (readwrite, nonatomic, copy) ZCURLSessionDidBecomeInvalidBlock sessionDidBecomeInvalid;
@property (readwrite, nonatomic, copy) ZCURLSessionDidReceiveAuthenticationChallengeBlock sessionDidReceiveAuthenticationChallenge;
@property (readwrite, nonatomic, copy) ZCURLSessionDidFinishEventsForBackgroundURLSessionBlock didFinishEventsForBackgroundURLSession;
@property (readwrite, nonatomic, copy) ZCURLSessionTaskWillPerformHTTPRedirectionBlock taskWillPerformHTTPRedirection;
@property (readwrite, nonatomic, copy) ZCURLSessionTaskDidReceiveAuthenticationChallengeBlock taskDidReceiveAuthenticationChallenge;
@property (readwrite, nonatomic, copy) ZCURLSessionTaskNeedNewBodyStreamBlock taskNeedNewBodyStream;
@property (readwrite, nonatomic, copy) ZCURLSessionTaskDidSendBodyDataBlock taskDidSendBodyData;
@property (readwrite, nonatomic, copy) ZCURLSessionTaskDidCompleteBlock taskDidComplete;
@property (readwrite, nonatomic, copy) ZCURLSessionDataTaskDidReceiveResponseBlock dataTaskDidReceiveResponse;
@property (readwrite, nonatomic, copy) ZCURLSessionDataTaskDidBecomeDownloadTaskBlock dataTaskDidBecomeDownloadTask;
@property (readwrite, nonatomic, copy) ZCURLSessionDataTaskDidReceiveDataBlock dataTaskDidReceiveData;
@property (readwrite, nonatomic, copy) ZCURLSessionDataTaskWillCacheResponseBlock  dataTaskWillCacheResponse;
@property (readwrite, nonatomic, copy) ZCURLSessionDownloadTaskDidFinishDownloadBlock downloadTaskDidFinishDownloading;
@property (readwrite, nonatomic, copy) ZCURLSessionDownloadTaskDidWriteDataBlock downloadTaskDidWriteData;
@property (readwrite, nonatomic, copy) ZCURLSessionDownloadTaskDidResumBlock downloadTaskDidResume;
@end

@implementation ZCURLSessionManager

- (instancetype)init{
    return [self initWithSessionConfiguration:nil];
}

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    if (!configuration) {
        configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    }
    
    self.sessionConfiguration = configuration;
    
    self.operationQueue = [[NSOperationQueue alloc] init];
    self.operationQueue.maxConcurrentOperationCount = 1;
    
    self.session = [NSURLSession sessionWithConfiguration:self.sessionConfiguration delegate:self delegateQueue:self.operationQueue];
    
    self.responseSerializer = [ZCJSONResponseSerializer serializer];
    
    self.securityPolicy = [ZCSercurityPolicy defaultPolicy];
    
#if !TARGET_OS_WATCH    
    self.reachablityManager = [ZCNetworkReachabilityManager sharedManager];
#endif
    
    self.lock = [[NSLock alloc] init];
    self.lock.name = ZCURLSessionMangerLockName;
    
    [self.session getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> * _Nonnull dataTasks, NSArray<NSURLSessionUploadTask *> * _Nonnull uploadTasks, NSArray<NSURLSessionDownloadTask *> * _Nonnull downloadTasks) {
        for (NSURLSessionDataTask *task in dataTasks) {
            [self addDelegateForDataTask:task uploadProgress:nil downloadProgress:nil completionHandler:nil];
        }
        
        for (NSURLSessionUploadTask *uploadTask in uploadTasks) {
            [self addDelegateForUploadTask:uploadTask progress:nil completionHandler:nil];
        }
        
        for (NSURLSessionDownloadTask *downloadTask in downloadTasks) {
            [self addDelegateForDownloadTask:downloadTask progress:nil destination:nil completionHandler:nil];
        }
    }];
    
    return nil;
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 

- (NSString *)taskDescriptionForSessionTask{
    return [NSString stringWithFormat:@"%p", self];
}

- (void)taskDidResume:(NSNotification *)notification{
    NSURLSessionTask *task = notification.object;
    if ([task respondsToSelector:@selector(taskDescription)]) {
        if ([task.taskDescription isEqualToString:self.taskDescriptionForSessionTask]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZCNetworkingTaskDidResumeNotificaiton object:task];
            });
        }
    }
}

- (void)taskdidSuspend:(NSNotification *)notification{
    NSURLSessionTask *task = notification.object;
    if ([task respondsToSelector:@selector(taskDescription)]) {
        if ([task.taskDescription isEqualToString:self.taskDescriptionForSessionTask]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZCNetworkingTaskDidSuspendNotifiacition object:task];
            });
        }
    }
}

#pragma mark - 

- (ZCURLSessionManagerTaskDelegate *)delegateForTask:(NSURLSessionTask *)task{
    NSParameterAssert(task);
    
    ZCURLSessionManagerTaskDelegate *delegate = nil;
    [self.lock lock];
    delegate = self.mutableTaskDelegatesKeyedByTaskIndentifier[@(task.taskIdentifier)];
    [self.lock unlock];
    return delegate;
}


- (void)setDelegate:(ZCURLSessionManagerTaskDelegate *)delegate forTask:(NSURLSessionTask *)task{
    NSParameterAssert(task);
    NSParameterAssert(delegate);
    
    [self.lock lock];
    self.mutableTaskDelegatesKeyedByTaskIndentifier[@(task.taskIdentifier)] = delegate;
    [self addNotificationObserverForTask:task];
    [self.lock unlock];
}

- (void)addDelegateForDataTask:(NSURLSessionDataTask *)dataTask  uploadProgress:(nullable void (^)(NSProgress * uploadProgress))uploadProgressBlock downloadProgress:(nullable void (^)(NSProgress *downloadProgress))downlaodProgressBlock completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler{
    ZCURLSessionManagerTaskDelegate *delegate = [[ZCURLSessionManagerTaskDelegate alloc] initWithTask:dataTask];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;
    
    dataTask.taskDescription = self.taskDescriptionForSessionTask;
    [self setDelegate:delegate forTask:dataTask];
    
    delegate.uploadProgressBlock = uploadProgressBlock;
    delegate.downloadProgressBlock = downlaodProgressBlock;
}

- (void)addDelegateForUploadTask:(NSURLSessionUploadTask *)uploadTask progress:(void (^)(NSProgress *uploadProgress))uploadProgresssBlock completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError *error))completionHandler{
    ZCURLSessionManagerTaskDelegate *delegate = [[ZCURLSessionManagerTaskDelegate alloc] initWithTask:uploadTask];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;
    
    uploadTask.taskDescription = self.taskDescriptionForSessionTask;
    [self setDelegate:delegate forTask:uploadTask];
    
    delegate.uploadProgressBlock = uploadProgresssBlock;
}

- (void)addDelegateForDownloadTask:(NSURLSessionDownloadTask *)downloadTask progress:(void (^)(NSProgress *downloadProgress))downloadProgressBlock destination:(NSURL * (^)(NSURL *targetPath,  NSURLResponse *response))destination completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler{
    ZCURLSessionManagerTaskDelegate *delegate = [[ZCURLSessionManagerTaskDelegate alloc] initWithTask:downloadTask];
    delegate.manager = self;
    delegate.completionHandler = completionHandler;
    
    if (destination) {
        delegate.downloadTaskDidFinishDownloading = ^NSURL *(NSURLSession * __unused session, NSURLSessionDownloadTask *downloadTask, NSURL *locaiotn) {
            return destination(locaiotn, downloadTask.response);
        };
    }
    
    downloadTask.taskDescription = self.taskDescriptionForSessionTask;
    
    [self setDelegate:delegate forTask:downloadTask];
    delegate.downloadProgressBlock = downloadProgressBlock;
}

- (void)removeDelegateForTask:(NSURLSessionTask *)task{
    NSParameterAssert(task);
    
    [self.lock lock];
    [self removeNotificationObserverForTask:task];
    [self.mutableTaskDelegatesKeyedByTaskIndentifier removeObjectForKey:@(task.taskIdentifier)];
    [self.lock unlock];
}


#pragma mark - 

- (NSArray *)tasksForKeyPath:(NSString *)keyPath{
    __block NSArray *tasks = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [self.session getTasksWithCompletionHandler:^(NSArray<NSURLSessionDataTask *> * _Nonnull dataTasks, NSArray<NSURLSessionUploadTask *> * _Nonnull uploadTasks, NSArray<NSURLSessionDownloadTask *> * _Nonnull downloadTasks) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(dataTasks))]) {
            tasks = dataTasks;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(uploadTasks))]){
            tasks = uploadTasks;
        } else if ([keyPath isEqualToString:NSStringFromSelector(@selector(downloadTasks))]){
            tasks = downloadTasks;
        }  else if ([keyPath isEqualToString:NSStringFromSelector(@selector(tasks))]){
            tasks = [@[dataTasks, uploadTasks, downloadTasks] valueForKeyPath:@"unionOfArrats.self"];
        }
        
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return tasks;
}
//这几个地方 黑魔法使用的真是 666
- (NSArray *)tasks{
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)dataTasks{
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)uploadTasks{
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

- (NSArray *)downloadTasks{
    return [self tasksForKeyPath:NSStringFromSelector(_cmd)];
}

#pragma mark - 

- (void)invalidateSessionCancelingTasks:(BOOL)cancelPendingTasks{
    if (cancelPendingTasks) {
        [self.session invalidateAndCancel];
    } else {
        [self.session finishTasksAndInvalidate];
    }
}

#pragma mark - 

- (void)serResponseSerializer:(id <ZCURLResponseSerialization>)responseSerializer{
    NSParameterAssert(responseSerializer);
    
    _responseSerializer = responseSerializer;
}

#pragma mark - 

- (void)addNotificationObserverForTask:(NSURLSessionTask *)task{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskDidResume:) name:ZCRULSessionTaskDidResumeNotification object:task];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskdidSuspend:) name:ZCURLSessonTaskDidSuspendNotification object:task];

}

- (void)removeNotificationObserverForTask:(NSURLSessionTask *)task{
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ZCRULSessionTaskDidResumeNotification object:task];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ZCURLSessonTaskDidSuspendNotification object:task];
}

#pragma mark - 

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLResponse *response, id responseObjecet, NSError *error))completionHandler{
    return [self dataTaskWithRequest:request uploadProgress:nil downloadPorgress:nil completionHandler:completionHandler];
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                               uploadProgress:(nullable void (^)(NSProgress *uploadProgress))uploadProgressBlock
                             downloadPorgress:(nullable void (^)(NSProgress *downloadProgress))downloadProgressBlock
                            completionHandler:(nullable void (^)(NSURLResponse * response, id _Nullable responseObject, NSError * _Nullable error))completionHandler{
    __block NSURLSessionDataTask *dataTask = nil;
    url_session_manager_create_task_safely(^{
        dataTask = [self.session dataTaskWithRequest:request];
    });
    
    [self addDelegateForDataTask:dataTask uploadProgress:uploadProgressBlock downloadProgress:downloadProgressBlock completionHandler:completionHandler];
    
    return dataTask;
}

#pragma mark -

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *)fileURL
                                         progress:(void (^)(NSProgress *uploadProgress))uploadProgressBlock
                                completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError * _Nullable error))completionHandler{
    __block NSURLSessionUploadTask *uploadTask = nil;
    url_session_manager_create_task_safely(^{
        uploadTask = [self.session uploadTaskWithRequest:request fromFile:fileURL];
    });
    
    if (!uploadTask && self.attemptsToRecreateUploadTasksForBackgroundSessions && self.session.configuration.identifier) {
        for (NSUInteger attempts = 0; !uploadTask && attempts < ZCMaximumNumberOfAttemptsToRecreateBackgorundSessionUploadTask; attempts++) {
            uploadTask = [self.session uploadTaskWithRequest:request fromFile:fileURL];
        }
    }
    
    [self addDelegateForUploadTask:uploadTask progress:uploadProgressBlock completionHandler:completionHandler];
    
    return uploadTask;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(nullable NSData *)bodyData
                                         progress:(nullable void (^)(NSProgress *uploadProgress))uploadProgressBlock
                                completionHandler:(nonnull void (^)(NSURLResponse *response, id responseObject, NSError * _Nullable error))completionHandler{
    __block NSURLSessionUploadTask *uploadTask = nil;
    url_session_manager_create_task_safely(^{
        uploadTask = [self.session uploadTaskWithRequest:request fromData:bodyData];
    });
    
    [self addDelegateForUploadTask:uploadTask progress:uploadProgressBlock completionHandler:completionHandler];
    
    return uploadTask;
}

- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request
                                                 progress:(void (^)(NSProgress * uploadProgress))uploadProgressBlock
                                        completionHandler:(void (^)(NSURLResponse *response, id responseObject, NSError * _Nullable error))completionHandler{
    __block NSURLSessionUploadTask *uploadTask = nil;
    url_session_manager_create_task_safely(^{
        uploadTask = [self.session uploadTaskWithStreamedRequest:request];
    });
    
    [self addDelegateForUploadTask:uploadTask progress:uploadProgressBlock completionHandler:completionHandler];
    
    return uploadTask;
}

#pragma mark - 
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                             progress:(void (^)(NSProgress *downloadPorgress))downloadProgressBlock
                                          destinaiton:(NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                                    completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler{
    __block NSURLSessionDownloadTask *downloadTask = nil;
    url_session_manager_create_task_safely(^{
        downloadTask = [self.session downloadTaskWithRequest:request];
    });
    
    [self addDelegateForDownloadTask:downloadTask progress:downloadProgressBlock destination:destination completionHandler:completionHandler];
    
    return downloadTask;
}

- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData
                                                progress:(void (^)(NSProgress *downloadProgress))downloadProgressBlock
                                             destination:(NSURL *(^)(NSURL *targetPath, NSURLResponse *response))destination
                                       completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler{
    __block NSURLSessionDownloadTask *downloadTask = nil;
    url_session_manager_create_task_safely(^{
        downloadTask = [self.session downloadTaskWithResumeData:resumeData];
    });
    
    [self addDelegateForDownloadTask:downloadTask progress:downloadProgressBlock destination:destination completionHandler:completionHandler];
    
    return downloadTask;
}

#pragma mark - 

- (NSProgress *)uploadProgressForTask:(NSURLSessionTask *)task{
    return [[self delegateForTask:task] uploadProgress];
}

- (NSProgress *)downloadProgressForTask:(NSURLSessionTask *)task{
    return [[self delegateForTask:task] downloadPorgress];
}

#pragma mark - 

- (void)setSessionDidBecomeInvalidBlock:(void (^)(NSURLSession * _Nonnull, NSError * _Nonnull))block{
    self.sessionDidBecomeInvalid = block;
}

- (void)setSeesionDidRecevieAuthenticationChallengeBlock:(NSURLSessionAuthChallengeDisposition (^)(NSURLSession * _Nonnull, NSURLAuthenticationChallenge * _Nonnull, NSURLCredential *__autoreleasing  _Nullable * _Nullable))block{
    self.sessionDidReceiveAuthenticationChallenge = block;
}

- (void)setDidFinishEventsForBackgroundURLSessionBlock:(void (^)(NSURLSession * _Nonnull))block{
    self.didFinishEventsForBackgroundURLSession = block;
}
#pragma mark - 

- (void)setTaskNeedNewBodyStreamBlock:(NSInputStream * _Nonnull (^)(NSURLSession *session, NSURLSessionTask *task))block{
    self.taskNeedNewBodyStream = block;
}

- (void)setTaskWillPerfromHTTPRedirectionBlock:(NSURLRequest * _Nonnull (^)(NSURLSession *session, NSURLSessionTask *task, NSURLResponse *response, NSURLRequest *request))block{
    self.taskWillPerformHTTPRedirection = block;
}

- (void)setTaskDidReceiveAuthenticationChallengeBlock:(NSURLSessionAuthChallengeDisposition (^)(NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, NSURLCredential *__autoreleasing  *credential ))block{
    self.taskDidReceiveAuthenticationChallenge = block;
}

- (void)setTaskDidSendBodyDataBlock:(void (^)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalbytesSent, int64_t totalBytesExpectedToSend))block{
    self.taskDidSendBodyData = block;
}

- (void)setTaskDidCompleteBlock:(void (^)(NSURLSession *session, NSURLSessionTask *task, NSError *error))block{
    self.taskDidComplete = block;
}

#pragma mark - 

- (void)setDataTaskDidReceiveResponseBlock:(NSURLSessionResponseDisposition (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response))block{
    self.dataTaskDidReceiveResponse = block;
}

- (void)setDataTaskDidBecomeDownloadTaskBlock:(void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask))block{
    self.dataTaskDidBecomeDownloadTask = block;
}

- (void)setDataTaskDidReceiveDataBlock:(void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data))block{
    self.dataTaskDidReceiveData = block;
}

- (void)setDataTaskWillChangeResponseBlock:(NSCachedURLResponse * _Nonnull (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSCachedURLResponse *proposedResponse))block{
    self.dataTaskWillCacheResponse = block;
}

#pragma mark -

- (void)setDownloadTaskDidFinishDownloadingBlock:(NSURL * _Nullable (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadtask, NSURL *locaiton))block{
    self.downloadTaskDidFinishDownloading = block;
}

- (void)setDownloadTaskDidWritDataBlock:(void (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite))block{
    self.downloadTaskDidWriteData = block;
}

- (void)setDownloadTaskDidResumBcok:(void (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t fileOffset, int64_t ecpectedTotalBytes))blocks{
    self.downloadTaskDidResume = blocks;
}

#pragma mark - NSObject

- (NSString *)description{
    return [NSString stringWithFormat:@"<%@: %p, session: %@, operationQueue: %@>", NSStringFromClass([self class]), self, self.session, self.operationQueue];
}

- (BOOL)respondsToSelector:(SEL)aSelector{

    return [[self class] instanceMethodForSelector:aSelector];
}

#pragma mark - NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error{
    if (self.sessionDidBecomeInvalid) {
        self.sessionDidBecomeInvalid(session, error);
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ZCURLSessionDidInvalidateNotificaiton object:session];
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler{
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;
    
    if (self.sessionDidReceiveAuthenticationChallenge) {
        disposition = self.sessionDidReceiveAuthenticationChallenge(session, challenge, &credential);
    } else {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
                if (credential) {
                    disposition = NSURLSessionAuthChallengeUseCredential;
                } else {
                    disposition = NSURLSessionAuthChallengePerformDefaultHandling;
                }
            } else {
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    }
    
    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler{
    NSURLRequest *redirectRequest = request;
    
    if (self.taskWillPerformHTTPRedirection) {
        redirectRequest = self.taskWillPerformHTTPRedirection(session, task, response, request);
    }
    
    if (completionHandler) {
        completionHandler(redirectRequest);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler{
    NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
    __block NSURLCredential *credential = nil;
    
    if (self.taskDidReceiveAuthenticationChallenge) {
        disposition = self.taskDidReceiveAuthenticationChallenge(session, task, challenge, &credential);
    } else {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            if ([self.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                disposition = NSURLSessionAuthChallengeUseCredential;
                credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            } else{
                disposition = NSURLSessionAuthChallengeCancelAuthenticationChallenge;
            }
        } else{
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
    }
    
    if (completionHandler) {
        completionHandler(disposition, credential);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
 needNewBodyStream:(void (^)(NSInputStream * _Nullable))completionHandler{
    NSInputStream *inputStream = nil;
    
    if (self.taskNeedNewBodyStream) {
        inputStream = self.taskNeedNewBodyStream(session, task);
    } else if (task.originalRequest.HTTPBodyStream && [task.originalRequest.HTTPBodyStream conformsToProtocol:@protocol(NSCopying)]){
        inputStream = [task.originalRequest.HTTPBodyStream copy];
    }
    
    if (completionHandler) {
        completionHandler(inputStream);
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
   didSendBodyData:(int64_t)bytesSent
    totalBytesSent:(int64_t)totalBytesSent
totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend{
    int64_t totalUnitCount = totalBytesExpectedToSend;
    if (totalUnitCount == NSURLSessionTransferSizeUnknown) {
        NSString *contentLength = [task.originalRequest valueForHTTPHeaderField:@"Content-Length"];
        if (contentLength) {
            totalUnitCount = (int64_t) [contentLength longLongValue];
        }
    }
    
    ZCURLSessionManagerTaskDelegate *delegate = [self delegateForTask:task];
    
    if (delegate) {
        [delegate URLSession:session task:task didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
    }
    
    if (self.taskDidSendBodyData) {
        self.taskDidSendBodyData(session, task, bytesSent, totalBytesSent, totalBytesExpectedToSend);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error{
    ZCURLSessionManagerTaskDelegate *delegate = [self delegateForTask:task];
    
    if (delegate) {
        [delegate URLSession:session task:task didCompleteWithError:error];
        
        [self removeDelegateForTask:task];
    }
    
    if (self.taskDidComplete) {
        self.taskDidComplete(session, task, error);
    }
    
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler{
    NSURLSessionResponseDisposition disposition = NSURLSessionResponseAllow;
    
    if (self.dataTaskDidReceiveResponse) {
        disposition = self.dataTaskDidReceiveResponse(session, dataTask, response);
    }
    
    if (completionHandler) {
        completionHandler(disposition);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didBecomeDownloadTask:(NSURLSessionDownloadTask *)downloadTask{
    ZCURLSessionManagerTaskDelegate *delegate = [self delegateForTask:dataTask];
    if (delegate) {
        [self removeDelegateForTask:dataTask];
        [self setDelegate:delegate forTask:downloadTask];
    }
    
    if (self.dataTaskDidBecomeDownloadTask) {
        self.dataTaskDidBecomeDownloadTask(session, dataTask, downloadTask);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data{
    ZCURLSessionManagerTaskDelegate *delegate = [self delegateForTask:dataTask];
    [delegate URLSession:session dataTask:dataTask didReceiveData:data];
    
    if (self.dataTaskDidReceiveData) {
        self.dataTaskDidReceiveData(session, dataTask, data);
    }
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse * _Nullable))completionHandler{
    NSCachedURLResponse *cachedResponse = proposedResponse;
    
    if (self.dataTaskWillCacheResponse) {
        cachedResponse = self.dataTaskWillCacheResponse(session, dataTask, proposedResponse);
    }
    
    if (completionHandler) {
        completionHandler(cachedResponse);
    }
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session{
    if (self.didFinishEventsForBackgroundURLSession) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.didFinishEventsForBackgroundURLSession(session);
        });
    }

}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location{
    ZCURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    if (self.downloadTaskDidFinishDownloading) {
        NSURL *fileURL = self.downloadTaskDidFinishDownloading(session, downloadTask, location);
        if (fileURL) {
            delegate.downloadFileURL = fileURL;
            NSError *error = nil;
            
            if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:fileURL error:&error]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:ZCURLSessioDownloadTaskDidFailToMoveFileNotification object:downloadTask userInfo:error.userInfo];
            }
            
            return;
        }
    }
    
    if (delegate) {
        [delegate URLSession:session downloadTask:downloadTask didFinishDownloadingToURL:location];
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite{
    ZCURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    
    if (delegate) {
        [delegate URLSession:session downloadTask:downloadTask didWriteData:bytesWritten totalBytesWritten:totalBytesWritten totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
    
    if (self.downloadTaskDidWriteData) {
        self.downloadTaskDidWriteData(session, downloadTask, bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes{
    ZCURLSessionManagerTaskDelegate *delegate = [self delegateForTask:downloadTask];
    
    if (delegate) {
        [delegate URLSession:session downloadTask:downloadTask didResumeAtOffset:fileOffset expectedTotalBytes:expectedTotalBytes];
    }
    
    if (self.downloadTaskDidResume) {
        self.downloadTaskDidResume(session, downloadTask, fileOffset, expectedTotalBytes);
    }
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    NSURLSessionConfiguration *configuration = [aDecoder decodeObjectOfClass:[NSURLSessionConfiguration class] forKey:@"sessionConfiguration"];
    
    self = [self initWithSessionConfiguration:configuration];
    if (!self) {
        return nil;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.session.configuration forKey:@"sessionConfiguration"];
}


#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone{
    return [[[self class] allocWithZone:zone] initWithSessionConfiguration:self.session.configuration];
}
@end
