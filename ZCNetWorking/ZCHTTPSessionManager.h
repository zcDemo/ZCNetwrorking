//
//  ZCHTTPSessionManager.h
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import "ZCURLSessionManager.h"
#if !TARGET_OS_WATCH
#import <SystemConfiguration/SystemConfiguration.h>
#endif
#import <TargetConditionals.h>

#if TAGET_OS_IOS || TARGET_OS_WATCH || TAGET_OS_TV
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <MobileCoreServices/MobileCoreServices.h>
#endif

#import "ZCURLSessionManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZCHTTPSessionManager : ZCURLSessionManager <NSSecureCoding, NSCopying>

@property (readonly, nonatomic, strong, nullable) NSURL *baseURL;

@property (nonatomic, strong) ZCHTTPRequestSerializer <ZCURLRequsetSerialization> *requestSerializer;

@property (nonatomic, strong) ZCHTTPResponseSerializer <ZCURLResponseSerialization> *responseSerializer;

@property (nonatomic, strong) ZCSercurityPolicy *securityPolicy;

+ (instancetype)manager;

- (instancetype)initWithBaseURL:(nullable NSURL*)url;

- (instancetype)initWithBaseURL:(nullable NSURL *)url sessionConfiguration:(nullable NSURLSessionConfiguration *)configuration NS_DESIGNATED_INITIALIZER;

/**
    @name Making HTTP Requests
 */

- (nullable NSURLSessionDataTask *)GET:(NSString *)URLString
                            parameters:(nullable id)parameters
                               success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                               failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure
    DEPRECATED_ATTRIBUTE;


- (nullable NSURLSessionDataTask *)GET:(NSString *)URLString
                            parameters:(nullable id)parameters
                              progress:(nullable void (^)(NSProgress *downloadProgress))downloadProgress
                               success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                               failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure;

- (nullable NSURLSessionDataTask *)HEAD:(NSString *)URLString
                             parameters:(nullable id)parameters
                                success:(nullable void (^)(NSURLSessionDataTask *task))success
                                failure:(nullable void (^)(NSURLSessionDataTask *_Nullable task, NSError *error))failure;

- (nullable NSURLSessionDataTask *)POST:(NSString *)URLString
                              parameter:(nullable id)parameters
                                success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                                failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure DEPRECATED_ATTRIBUTE;

- (nullable NSURLSessionDataTask *)POST:(NSString *)URLString
                             parameters:(nullable id)parameters
                               progress:(nullable void (^)(NSProgress *uploadProgress))uploadProgress
                                success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                                failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure;

- (nullable NSURLSessionDataTask *)POST:(NSString *)URLString
                             parameters:(nullable id)parameters
              constructingBodyWithBlock:(nullable void (^)(id <ZCMultipartFormData> formData))block
                                success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                                failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure DEPRECATED_ATTRIBUTE;

- (nullable NSURLSessionDataTask *)POST:(NSString *)URLString
                             parameters:(nullable id)parameters
                  constructingBodyBlock:(nullable void (^)(id <ZCMultipartFormData> formData))block
                               progress:(nullable void (^)(NSProgress *uploadProgress))uploadProgress
                                success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObjcet))success
                                failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure;

- (nullable NSURLSessionDataTask *)PUT:(NSString *)URLString
                            parameters:(nullable id)parameters
                               success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                               failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure;


- (nullable NSURLSessionDataTask *)PATCH:(NSString *)URLString
                              parameters:(nullable id)parameters
                                 success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                                 failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure;

- (nullable NSURLSessionDataTask *)DELETE:(NSString *)URLString
                               parameters:(nullable id)parameters
                                  success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))sucess
                                  failure:(nullable void (^)(NSURLSessionDataTask *_Nullable task, NSError *error))failure;
@end

NS_ASSUME_NONNULL_END
