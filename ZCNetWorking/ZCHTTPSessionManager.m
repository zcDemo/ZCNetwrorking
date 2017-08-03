//
//  ZCHTTPSessionManager.m
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import "ZCHTTPSessionManager.h"

#import "ZCURLRequestSerialization.h"
#import "ZCURLResponseSerialization.h"

#import <Availability.h>
#import <TargetConditionals.h>
#import <Security/Security.h>

#import <netinet/in.h>
#import <netinet6/in6.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <netdb.h>

#if  TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#elif TARGET_OS_WATCH
#import <WatchKit/WatchKit.h>
#endif

@interface ZCHTTPSessionManager ()
@property (readwrite, nonatomic, strong) NSURL *baseURL;
@end

@implementation ZCHTTPSessionManager
@dynamic responseSerializer;

+ (instancetype)manager{
    return [[[self class] alloc] initWithBaseURL:nil];
}


- (instancetype)init{
    return [self initWithBaseURL:nil];
}

- (instancetype)initWithBaseURL:(NSURL *)url{
    return [self initWithBaseURL:url sessionConfiguration:nil];
}

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration{
    return [self initWithBaseURL:nil sessionConfiguration:configuration];
}

- (instancetype)initWithBaseURL:(NSURL *)url sessionConfiguration:(NSURLSessionConfiguration *)configuration{
    self = [super initWithSessionConfiguration:configuration];
    if (!self) {
        return  nil;
    }
    
    if ([[url path] length] > 0 && ![[url absoluteString] hasSuffix:@"/"]) {
        url = [url URLByAppendingPathComponent:@""];
    }
    
    self.baseURL = url;
    
    self.requesSerializer = [ZCHTTPRequestSerializer serializer];
    self.responseSerializer = [ZCHTTPResponseSerializer serializer];
    
    return self;
}


#pragma mark - 

- (void)setRequesSerializer:(ZCHTTPRequestSerializer<ZCURLRequsetSerialization> *)requestSerializer{
    NSParameterAssert(requestSerializer);
    
    _requestSerializer = requestSerializer;
}

- (void)setResponseSerializer:(ZCHTTPResponseSerializer<ZCURLResponseSerialization> *)responseSerializer{
    NSParameterAssert(responseSerializer);
    
    [super setResponseSerializer:responseSerializer];
}

@dynamic securityPolicy;

- (void)setSecurityPolicy:(ZCSercurityPolicy *)securityPolicy{
    if (securityPolicy.SSLPinningMode != ZCSSLPinningModeNone && ![self.baseURL.scheme isEqualToString:@"https"]) {
        NSString *pinningMode = @"Unknown Pinning Mode";
        switch (securityPolicy.SSLPinningMode) {
            case ZCSSLPinningModeNone:
                pinningMode = @"ZCSSLPinningModeNone";
                break;
            case ZCSSLPinningModePublicKey:
                pinningMode = @"ZCSSLPinningModePublicKey";
                break;
            case ZCSSLPinningModeCertificate:
                pinningMode = @"ZCSSLPinningModeCertificate";
                break;
        }
        NSString *reason = [NSString stringWithFormat:@"A security policy congfigured with '%@' can only be applied on a  manager with a secure base URL (i.e.https)", pinningMode];
        @throw [NSException exceptionWithName:@"Invalid Security Policy" reason:reason userInfo:nil];
    }
    [super setSecurityPolicy:securityPolicy];
}

#pragma mark - 

- (NSURLSessionDataTask *)GET:(NSString *)URLString
                   parameters:(id)parameters
                      success:(void (^)(NSURLSessionDataTask *task, id  responseObject))success
                      failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure{
    return [self GET:URLString parameters:parameters progress:nil success:success failure:failure];
}

- (NSURLSessionDataTask *)GET:(NSString *)URLString
                   parameters:(id)parameters
                     progress:(void (^)(NSProgress * _Nonnull))downloadProgress
                      success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))success
                      failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure{
    NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"GET" URLString:URLString parameters:parameters uploadProgress:nil downloadProgress:downloadProgress success:success failure:failure];
    [dataTask resume];
    
    return dataTask;
}

- (NSURLSessionDataTask *)HEAD:(NSString *)URLString
                    parameters:(id)parameters
                       success:(void (^)(NSURLSessionDataTask *task))success
                       failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure{
    NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"HEAD" URLString:URLString parameters:parameters uploadProgress:nil downloadProgress:nil success:^(NSURLSessionDataTask *task, __unused id responseObject) {
        if (success) {
            success(task);
        }
    } failure:failure];
    
    [dataTask resume];
    
    return dataTask;
}

- (NSURLSessionDataTask *)POST:(NSString *)URLString
                     parameter:(id)parameters
                       success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
                       failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure{
    return [self POST:URLString parameters:parameters progress:nil success:success failure:failure];
}

- (NSURLSessionDataTask *)POST:(NSString *)URLString
                    parameters:(id)parameters
                      progress:(void (^)(NSProgress * _Nonnull))uploadProgress
                       success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))success
                       failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure{
    NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"POST" URLString:URLString parameters:parameters uploadProgress:uploadProgress downloadProgress:nil success:success failure:failure];
    
    return dataTask;
}

- (NSURLSessionDataTask *)POST:(NSString *)URLString
                    parameters:(id)parameters
     constructingBodyWithBlock:(void (^)(id<ZCMultipartFormData> _Nonnull))block
                       success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))success
                       failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure{
    return [self POST:URLString parameters:parameters constructingBodyBlock:block progress:nil success:success failure:failure];
}

-  (NSURLSessionDataTask *)POST:(NSString *)URLString
                     parameters:(id)parameters
          constructingBodyBlock:(void (^)(id<ZCMultipartFormData> _Nonnull))block
                       progress:(void (^)(NSProgress * _Nonnull))uploadProgress
                        success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))success
                        failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure{
    NSError *serializationError = nil;
    NSMutableURLRequest *request = [self.requestSerializer multipartFormRequsetWithMethod:@"POST" URLString:[[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString] parameters:parameters constructionBodyWithBlock:block error:&serializationError];
    if (serializationError) {
        if (failure) {
            dispatch_async(self.completionQueue ?:dispatch_get_main_queue(), ^{
                failure(nil, serializationError);
            });
        }
    }
    
    __block NSURLSessionDataTask *task = [self uploadTaskWithStreamedRequest:request progress:uploadProgress completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) {
                failure(task, error);
            }
        } else {
            if (success) {
                success(task, responseObject);
            }
        }
    }];
    
    [task resume];
    
    return task;
}

-(NSURLSessionDataTask *)PUT:(NSString *)URLString
                  parameters:(id)parameters
                     success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))success
                     failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure{
    NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"PUT" URLString:URLString parameters:parameters uploadProgress:nil downloadProgress:nil success:success failure:failure];
    
    [dataTask resume];
    
    return dataTask;
}

- (NSURLSessionDataTask *)PATCH:(NSString *)URLString
                     parameters:(id)parameters
                        success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))success
                        failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure{
    NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"PACTH" URLString:URLString parameters:parameters uploadProgress:nil downloadProgress:nil success:success failure:failure];
    
    [dataTask resume];
    
    return dataTask;
}

- (NSURLSessionDataTask *)DELETE:(NSString *)URLString
                      parameters:(id)parameters
                         success:(void (^)(NSURLSessionDataTask * _Nonnull, id _Nullable))sucess
                         failure:(void (^)(NSURLSessionDataTask * _Nullable, NSError * _Nonnull))failure{
    NSURLSessionDataTask *dataTask = [self dataTaskWithHTTPMethod:@"DELETE" URLString:URLString parameters:parameters uploadProgress:nil downloadProgress:nil success:sucess failure:failure];
    
    [dataTask resume];
    
    return dataTask;
}

- (NSURLSessionDataTask *)dataTaskWithHTTPMethod:(NSString *)method
                                       URLString:(NSString *)URLString
                                      parameters:(id)parameters
                                  uploadProgress:(nullable void (^)(NSProgress *uploadProgress))uploadProgress
                                downloadProgress:(nullable void (^)(NSProgress *downloadProgress))downloadProgress
                                         success:(void (^)(NSURLSessionDataTask *, id))success
                                         failure:(void (^)(NSURLSessionDataTask *, NSError *))failure{
    NSError *serializationError = nil;
    NSMutableURLRequest *request = [self.requestSerializer requstWithMethod:method URLString:[[NSURL URLWithString:URLString relativeToURL:self.baseURL] absoluteString]parameters:parameters error:&serializationError];
    if (serializationError) {
        if (failure) {
            dispatch_async(self.completionQueue ?:dispatch_get_main_queue(), ^{
                failure(nil, serializationError);
            });
        }
        return nil;
    }
    
    __block NSURLSessionDataTask *dataTask = nil;
    dataTask = [self dataTaskWithRequest:request uploadProgress:uploadProgress downloadPorgress:downloadProgress completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if (error) {
            if (failure) {
                failure(dataTask, error);
            }
        } else {
            if (success) {
                success(dataTask, responseObject);
            }
        }
    }];
    
    return dataTask;
}

#pragma mark - NSObject

- (NSString *)description{
    return [NSString stringWithFormat:@"<%@: %p, baseURL: %@, sessinL %@, operationQueue: %@>", NSStringFromClass([self class]), self, [self.baseURL absoluteString], self.session, self.operationQueue];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    NSURL *baseURL = [aDecoder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(baseURL))];
    NSURLSessionConfiguration *configuration = [aDecoder decodeObjectOfClass:[NSURLSessionConfiguration class] forKey:@"sessionConfiguration"];
    if (!configuration) {
        NSString *configurationIdentifier = [aDecoder decodeObjectOfClass:[NSString class] forKey:@"identifier"];
        if (configurationIdentifier) {
#if (defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED >= 80000) || (defined(__MAC_OS_X_VERSION_MIN_REQUIRED) && __MAC_OS_X_VERSION_MIN_REQUIRED >= 1100)
            configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:configurationIdentifier];
#else
            configurationIdentifier = [NSURLSessionConfiguration backgroundSessionConfiguration:configurationIdentifier];
#endif
        }
    }
    
    self = [self initWithBaseURL:baseURL sessionConfiguration:configuration];
    if (!self) {
        return nil;
    }
    
    self.requestSerializer = [aDecoder decodeObjectOfClass:[ZCHTTPRequestSerializer class] forKey:NSStringFromSelector(@selector(requestSerializer))];
    self.responseSerializer = [aDecoder decodeObjectOfClass:[ZCHTTPResponseSerializer class] forKey:NSStringFromSelector(@selector(responseSerializer))];
    ZCSercurityPolicy *decodedPolicy = [aDecoder decodeObjectOfClass:[ZCSercurityPolicy class] forKey:NSStringFromSelector(@selector(securityPolicy))];
    if (decodedPolicy) {
        self.securityPolicy = decodedPolicy;
    }
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [super encodeWithCoder:aCoder];
    
    [aCoder encodeObject:self.baseURL forKey:NSStringFromSelector(@selector(baseURL))];
    if ([self.session.configuration conformsToProtocol:@protocol(NSCoding)]) {
        [aCoder encodeObject:self.session.configuration forKey:@"sessionConfiguration"];
    } else {
        [aCoder encodeObject:self.session.configuration.identifier forKey:@"identifier"];
    }
    
    [aCoder encodeObject:self.responseSerializer forKey:NSStringFromSelector(@selector(requestSerializer))];
    [aCoder encodeObject:self.responseSerializer forKey:NSStringFromSelector(@selector(responseSerializer))];
    [aCoder encodeObject:self.securityPolicy forKey:NSStringFromSelector(@selector(securityPolicy))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone{
    ZCHTTPSessionManager *HTTPClient = [[[self class] allocWithZone:zone] initWithBaseURL:self.baseURL sessionConfiguration:self.session.configuration];
    
    HTTPClient.requestSerializer = [self.requestSerializer copyWithZone:zone];
    HTTPClient.responseSerializer = [self.responseSerializer copyWithZone:zone];
    HTTPClient.securityPolicy = [self.securityPolicy copyWithZone:zone];
    return HTTPClient;
}
@end
