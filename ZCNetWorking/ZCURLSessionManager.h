//
//  ZCURLSessionManager.h
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZCURLRequestSerialization.h"
#import "ZCURLResponseSerialization.h"
#import "ZCSercurityPolicy.h"
#if  !TARGET_OS_WATCH
#import "ZCNetworkReachabilityManager.h"
#endif

NS_ASSUME_NONNULL_BEGIN
@interface ZCURLSessionManager : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate, NSSecureCoding, NSCopying>

/**
 The managed session.
 */
@property (readonly, nonatomic, strong) NSURLSession *session;

/**
 The operation queue on which delegate callbacks are run.
 */
@property (readonly, nonatomic, strong) NSOperationQueue *operationQueue;

@property (nonatomic, strong) id <ZCURLResponseSerialization> responseSerializer;

@property (nonatomic, strong) ZCSercurityPolicy *securityPolicy;

#if !TARGER_OS_WATCH
@property (readwrite, nonatomic, strong) ZCNetworkReachabilityManager *reachablityManager;
#endif


/**
    @name Getting Session Task
    获取session任务
 */
@property (readonly, nonatomic, strong) NSArray <NSURLSessionTask *> *tasks;

@property (readonly, nonatomic, strong) NSArray <NSURLSessionDataTask *> *dataTask;

@property (readonly, nonatomic, strong) NSArray <NSURLSessionUploadTask *> *uploadTask;

@property (readonly, nonatomic, strong) NSArray<NSURLSessionDownloadTask *> *downloadTasks;

/**
    @name Managing Callback Queues
    管理回调队列
 */
@property (nonatomic, strong, nullable) dispatch_queue_t completionQueue;

@property (nonatomic, strong, nullable) dispatch_group_t completionGroup;


@property (nonatomic, assign) BOOL attemptsToRecreateUploadTasksForBackgroundSessions;


/**
    @name Initialization
 */
- (instancetype)initWithSessionConfiguration:(nullable NSURLSessionConfiguration *)configuration
    NS_DESIGNATED_INITIALIZER;

- (void)invalidateSessionCancelingTasks:(BOOL)cancelPendingTasks;

/**
    @name Running Data Tasks
 */
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(nullable void(^)(NSURLResponse *response, id _Nullable responseObject, NSError *_Nullable error))completionHandler;

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)requset
                               uploadProgress:(nullable void(^)(NSProgress *uploadProgress))uploadProgressBlock
                             downloadPorgress:(nullable void(^)(NSProgress *downloadProgress))downloadProgressBlock
                            completionHandler:(nullable void(^)(NSURLResponse *response, id _Nullable responseObject, NSError * _Nullable error))completionHandler;

/**
 @name Running Upload Tasks
 */
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromFile:(NSURL *) fileURL
                                         progress:(nullable void(^)(NSProgress *uploadProgress))uploadProgressBlock
                                completionHandler:(nullable void(^)(NSURLResponse *response, id _Nullable responseObject, NSError * _Nullable error))completionHandler;

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request
                                         fromData:(nullable NSData *)bodyData
                                         progress:(nullable void (^)(NSProgress *uploadProgress))uploadProgressBlock
                                completionHandler:(nonnull void (^)(NSURLResponse *response, id responseObject,NSError * _Nullable error))completionHandler;

- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request
                                                 progress:(nullable void(^)(NSProgress *uploadProgress))uploadProgressBlock completionHandler:(nullable void(^)(NSURLResponse *response, id _Nullable responseObject, NSError * _Nullable error))completionHandler;

/**
 @name Running Download Tasks
 */
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request
                                             progress:(nullable void(^)(NSProgress * downloadProgress))downloadProgressBlock
                                          destinaiton:(nullable NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination
                                    completionHandler:(nullable void(^)(NSURLResponse * response, NSURL * _Nullable filePath, NSError * _Nullable error))completionHandler;

- (NSURLSessionDownloadTask *)downloadTaskWithResumeData:(NSData *)resumeData progress:(nullable void (^)(NSProgress *downloadProgress))downloadProgressBlock destination:(nullable NSURL * (^)(NSURL *targetPath, NSURLResponse *response))destination completionHandler:(nullable void (^)(NSURLResponse *response, NSURL * _Nullable filePath, NSError * _Nullable error))completionHandler;

/**
 @name Gettin Progress for Tasks
 */

- (nullable NSProgress *)uploadProgressForTask:(NSURLSessionTask *)task;

- (nullable NSProgress *)downloadProgressForTask:(NSURLSessionTask *)task;

/**
 @name Setting Session Delegate Callbacks
 */

- (void)setSessionDidBecomeInvalidBlock:(nullable void (^)(NSURLSession *session, NSError *error))block;

- (void)setSeesionDidRecevieAuthenticationChallengeBlock:(nullable NSURLSessionAuthChallengeDisposition (^)(NSURLSession *session, NSURLAuthenticationChallenge *challenge, NSURLCredential * _Nullable __autoreleasing * _Nullable credential))block;

/**
 @name Setting Task Delegate Callbacks
 */

- (void)setTaskNeedNewBodyStreamBlock:(nullable NSInputStream * (^)(NSURLSession *session, NSURLSessionTask *task))block;

- (void)setTaskWillPerfromHTTPRedirectionBlock:(nullable NSURLRequest * (^)(NSURLSession *session, NSURLSessionTask *task, NSURLResponse *response, NSURLRequest *request))block;

- (void)setTaskDidReceiveAuthenticationChallengeBlock:(nullable NSURLSessionAuthChallengeDisposition (^)(NSURLSession *session, NSURLSessionTask *task, NSURLAuthenticationChallenge *challenge, NSURLCredential * _Nullable __autoreleasing * _Nullable credential))block;

- (void)setTaskDidSendBodyDataBlock:(nullable void (^)(NSURLSession *session, NSURLSessionTask *task, int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend))block;

-  (void)setTaskDidCompleteBlock:(nullable void (^)(NSURLSession *session, NSURLSessionTask *task, NSError * _Nullable error))block;

/**
 @name Setting Data Task Delegate Callbacks
 */

- (void)setDataTaskDidReceiveResponseBlock:(nullable NSURLSessionResponseDisposition (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLResponse *response))block;

- (void)setDataTaskDidBecomeDownloadTaskBlock:(nullable void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSURLSessionDownloadTask *downloadTask))block;

- (void)setDataTaskDidReceiveDataBlock:(nullable void (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSData *data))block;

- (void)setDataTaskWillChangeResponseBlock:(nullable NSCachedURLResponse * (^)(NSURLSession *session, NSURLSessionDataTask *dataTask, NSCachedURLResponse *proposedResponse))block;

- (void)setDidFinishEventsForBackgroundURLSessionBlock:(nullable void (^)(NSURLSession *session))block;

/**
 @name Setting Download Task Delegate Callbacks
 */

- (void)setDownloadTaskDidFinishDownloadingBlock:(nullable NSURL * _Nullable (^)(NSURLSession *sessin, NSURLSessionDownloadTask *downloadTask, NSURL *location))block;

- (void)setDownloadTaskDidWritDataBlock:(nullable void (^)(NSURLSession *session, NSURLSessionDownloadTask *downloadTask, int64_t bytesWritten, int64_t totalBytesWritten, int64_t totalBytesExpectedToWrite))block;

- (void)setDownloadTaskDidResumBcok:(nullable void (^)(NSURLSession *session, NSURLSessionDownloadTask *download, int64_t fileOffset, int64_t expectedTotalBytes))blocks;

@end

/**
 @name Notification
 */

FOUNDATION_EXPORT NSString * const ZCNetworkingTaskDidResumeNotificaiton;

FOUNDATION_EXPORT NSString * const ZCNetworkingTaskDidCompleteNotification;

FOUNDATION_EXPORT NSString * const ZCNetworkingTaskDidSuspendNotifiacition;

FOUNDATION_EXPORT NSString * const
    ZCURLSessionDidInvalidateNotificaiton;

FOUNDATION_EXPORT NSString * const  ZCURLSessioDownloadTaskDidFailToMoveFileNotification;

FOUNDATION_EXPORT NSString * const ZCNetworkingTaskDidCompleteResponseDataKey;

FOUNDATION_EXPORT NSString * const ZCNetworkingTaskDidCompleteSerializedResponseKey;

FOUNDATION_EXPORT NSString * const ZCNetworkingTaskDidCompleteResponseSerializerKey;

FOUNDATION_EXPORT NSString * const ZCNetworkingTaskDidCompleteAssetPathKey;

FOUNDATION_EXPORT NSString * const ZCNetWorkingTaskDidCompleteErrorKey;

NS_ASSUME_NONNULL_END
