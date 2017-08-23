//
//  ZCURLRequestSerialization.h
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if  TARGET_OS_IOS || TARGET_OS_TV 
#import <UIKit/UIKit.h>
#elif TARGET_OS_WATCH
#import <WatchKit/WatchKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * ZCPercentEscapedStringFromString(NSString *string);
FOUNDATION_EXPORT NSString *ZCQueryStringFromParameters(NSDictionary *parameters);

@protocol ZCURLRequsetSerialization <NSObject, NSSecureCoding, NSCopying>

- (nullable NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                                        withParameters:(nullable id)parameters
                                                 error:(NSError * _Nullable __autoreleasing *)error NS_SWIFT_NOTHROW;
@end

#pragma mark - 

typedef NS_ENUM(NSUInteger, ZCHTTPRequestQueryStringSerialzationStyle){
    ZCHTTPRequestQueryStringDefaultStyle = 0,
};

@protocol ZCMultipartFormData;

@interface ZCHTTPRequestSerializer : NSObject <ZCURLRequsetSerialization>

@property (nonatomic, assign) NSStringEncoding stringEncoding;

@property (nonatomic, assign) BOOL allowsCellularAccess;

@property (nonatomic, assign) NSURLRequestCachePolicy cachePolicy;

@property (nonatomic, assign) BOOL HTTPShouldHandleCookies;

@property (nonatomic, assign) BOOL HTTPShouldUsePipeling;

@property (nonatomic, assign) NSURLRequestNetworkServiceType networkServiceType;

@property (nonatomic, assign) NSTimeInterval timeoutInterval;

/**
    @name Configuring HTTP Request Headers
 */

@property (readonly, nonatomic, strong) NSDictionary <NSString *, NSString *> *HTTPRequestHeaders;

+ (instancetype)serializer;

- (void)setValue:(nullable NSString *)value forHTTPHeaderField:(nonnull NSString *)field;

- (nullable NSString *)valueForHTTPHeaderField:(NSString *)field;

- (void)setAuthonrizationHeaderFieldWithUsername:(NSString *)username password:(NSString *)password;

- (void)clearAuthorizationHeader;

/**
    @name Configuring Query String Parameter Serialization
 */

@property (nonatomic, strong) NSSet <NSString *> *HTTPMethodsEncodingParametersInURI;

- (void)setQueryStringSerializationWithStyle:(ZCHTTPRequestQueryStringSerialzationStyle)style;

- (void)setQueryStringSerializationWithBlock:(nullable NSString * (^)(NSURLRequest *request, id parameters, NSError * __autoreleasing *error))block;

/**
    @name Creating Request Objects
 */

- (NSMutableURLRequest *)requstWithMethod:(NSString *)method
                                URLString:(NSString *)URLString
                               parameters:(nullable id)parameters
                                    error:(NSError *_Nullable __autoreleasing *)error;


- (NSMutableURLRequest *)multipartFormRequsetWithMethod:(NSString *)method
                                              URLString:(NSString *)URLString
                                             parameters:(nullable NSDictionary <NSString *, id> *)parameters
                              constructionBodyWithBlock:(nullable void (^)(id <ZCMultipartFormData>))block
                                                  error:(NSError * _Nullable __autoreleasing *)error;

- (NSMutableURLRequest *)requestWithMultipartFormRequest:(NSURLRequest *)request
                             writingStreamContentsToFile:(NSURL *)fileUR
                                       completionHandler:(nullable void (^)(NSError * _Nullable error))handler;

@end

#pragma mark -

@protocol ZCMultipartFormData

- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                        error:(NSError * _Nullable __autoreleasing *)error;

- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                     fileName:(NSString *)fileName
                     mineType:(NSString *)mimeType
                        error:(NSError * _Nullable __autoreleasing *)error;

- (BOOL)appendPartWithInputStream:(nullable NSInputStream *)inputStream
                             name:(NSString *)name
                         fileName:(NSString *)fileName
                           length:(int64_t)length
                         mineType:(NSString *)mimeType;

- (void)appendPartWithFromData:(NSData *)data
                          name:(NSString *)name
                      fileName:(NSString *)fileName
                      mimeType:(NSString *)mimeType;

- (void)appendPartWithFromData:(NSData *)data name:(NSString *)name;

- (void)appendPartWithHeaders:(nullable NSDictionary <NSString *, NSString *> *)headers body:(NSData *)body;

- (void)throttleBandwidthWithPacketSize:(NSUInteger)numberOfBytes delay:(NSTimeInterval)delay;
@end

#pragma mark -

@interface ZCJSONRequestSerializer : ZCHTTPRequestSerializer

@property (nonatomic, assign) NSJSONWritingOptions writingOptions;

+ (instancetype)serializerWithWritingOptions:(NSJSONWritingOptions)writingOptions;
@end

#pragma mark -

@interface ZCPropertyListRequestSerializer : ZCHTTPRequestSerializer

@property (nonatomic, assign) NSPropertyListFormat format;

@property (nonatomic, assign) NSPropertyListWriteOptions writeOptions;

+ (instancetype)serializerWithFormate:(NSPropertyListFormat)format
                         writeOptions:(NSPropertyListWriteOptions)writeOptions;

@end

#pragma mark - 

/**
    @name Constants
 */

FOUNDATION_EXPORT NSString * const ZCURLRequestSerializationErrorDomain;

FOUNDATION_EXPORT NSString * const ZCNetworkingOperationFailingURLRequsetErrorKey;

FOUNDATION_EXPORT NSUInteger const kZCUploadStream3GSuggestedPacketSize;
FOUNDATION_EXPORT NSTimeInterval constkZCUploadStream3GSuggestedDelay;

NS_ASSUME_NONNULL_END
