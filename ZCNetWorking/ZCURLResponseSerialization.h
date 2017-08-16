//
//  ZCURLResponseSerialization.h
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN //在这之间的对象为 nonull 如果为null或者为nil 编译器就会报出警告
@protocol ZCURLResponseSerialization <NSObject, NSSecureCoding, NSCopying>

- (nullable id)responseObjectForResponse:(nullable NSURLResponse *)response data:(nullable NSData *)data error:(NSError * _Nullable __autoreleasing *)error NS_SWIFT_NOTHROW;

@end

#pragma mark - 

@interface ZCHTTPResponseSerializer : NSObject <ZCURLResponseSerialization>

- (instancetype)init;

@property (nonatomic, assign) NSStringEncoding stringEncoding DEPRECATED_MSG_ATTRIBUTE("The string encoding is never used. AFHTTPResponseSerializer only validates status codes and content types but does not try to decode the received data in any way.");

+ (instancetype)serializer;

@property (nonatomic, copy, nullable) NSIndexSet *acceptableStatusCodes;

@property (nonatomic, copy, nullable) NSSet <NSString *> *acceptableContentTypes;

- (BOOL)validateResponse:(nullable NSHTTPURLResponse *)response
                    data:(nullable NSData *)data
                   error:(NSError * _Nullable __autoreleasing *)error;
@end

#pragma mark - 

@interface ZCJSONResponseSerializer :ZCHTTPResponseSerializer

- (instancetype)init;

@property (nonatomic, assign) NSJSONReadingOptions readingOptions;

@property (nonatomic, assign) BOOL removesKeysWithNullValues;

+ (instancetype)serializerWithReadingOptions:(NSJSONReadingOptions)readingOptions;
@end

#pragma mark -

@interface ZCXMLParserResponseSerializer : ZCHTTPResponseSerializer

@end

#pragma mark - 
#ifdef __MAC_OX_VERSION_MIN_REQUIRED
@interface ZCXMLDocumentrResponseSerializer : ZCHTTPResponseSerializer
- (instancetype)init;

@property (nonatomic, assign) NSUInteger options;

+ (instancetype)serializerWithXMLDocumentOptions:(NSUInteger)mask;
@end

#endif

#pragma mark - 

@interface ZCPropertyListResponseSerializer : ZCHTTPResponseSerializer
- (instancetype)init;

@property (nonatomic, assign) NSPropertyListFormat format;

@property (nonatomic, assign) NSPropertyListReadOptions readOptions;

+ (instancetype)serializerWithFormat:(NSPropertyListFormat)format readOptions:(NSPropertyListReadOptions)readOptions;

@end

#pragma mark - 

@interface ZCImageResponseSerializer : ZCHTTPResponseSerializer

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH
@property (nonatomic, assign) CGFloat imageScale;

@property (nonatomic, assign) BOOL automaticallyInflatesResponseImage;
#endif
@end

#pragma mark - 

@interface ZCCompoundResponseSerializer : ZCHTTPResponseSerializer

@property (readonly, nonatomic, copy) NSArray <id<ZCURLResponseSerialization>> *responseSerializer;

+ (instancetype)compoundSerailizerWithResponseSerializers:(NSArray <id <ZCURLResponseSerialization>> *)responseSerializers;

@end

/*
    @name Constants
 */

FOUNDATION_EXPORT NSString * const ZCURLResponseSerializerErrorDomain;

FOUNDATION_EXPORT NSString * const ZCNetworkingOperationFailingURLResponseErrorKey;

FOUNDATION_EXPORT NSString * const ZCNetworkingOpertaionFailingURLResponseDataErrorKey;

NS_ASSUME_NONNULL_END
