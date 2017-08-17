//
//  ZCURLResponseSerialization.m
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import "ZCURLResponseSerialization.h"
#import <TargetConditionals.h>

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#elif TARGET_OS_WATCH
#import <WatchKit/WatchKit.h>
#elif defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
#import <Cocoa/Cocoa.h>
#endif

NSString * const ZCURLResponseSerializationErrorDomain = @"com.zcnetworking.error.serialization.response";
NSString * const ZCNetworkingOperationFailingURLResponseErrorKey = @"com.zcnetworking.serializaton,response.error.response";
NSString * const ZCNerworkingOperationFailingURLResponseDataErrorKey = @"com.zcnetworking.serailzation.response.error.data";

static NSError * ZCErrorWithUnderlyingError(NSError *error, NSError *underlyingError){
    if (!error) {
        return  underlyingError;
    }
    
    if (!underlyingError || error.userInfo[NSUnderlyingErrorKey]) {
        return error;
    }
    
    NSMutableDictionary *mutableUserInfo = [error.userInfo mutableCopy];
    mutableUserInfo[NSUnderlyingErrorKey] = underlyingError;
    
    return [[NSError alloc] initWithDomain:error.domain code:error.code userInfo:mutableUserInfo];
}

static BOOL ZCErrorOrUnderlyingErrorHasCodeInDomain(NSError *error, NSInteger code, NSString *domain){
    if ([error.domain isEqualToString:domain] && error.code == code) {
        return YES;
    } else if (error.userInfo[NSUnderlyingErrorKey]){
        return ZCErrorOrUnderlyingErrorHasCodeInDomain(error.userInfo[NSUnderlyingErrorKey], code, domain);
    }
    
    return NO;
}

static id ZCJSONObjectByRemovingKeysWithNullValues(id JSONObject, NSJSONReadingOptions readingOptions){
    if ([JSONObject isKindOfClass:[NSArray class]]){
        NSMutableArray *mutableArray = [NSMutableArray arrayWithCapacity:[(NSArray *)JSONObject count]];
        for (id value in (NSArray *)JSONObject) {
            [mutableArray addObject:ZCJSONObjectByRemovingKeysWithNullValues(value, readingOptions)];
        }
        
        return (readingOptions & NSJSONReadingMutableContainers) ? mutableArray : [NSArray arrayWithArray:mutableArray];
    } else if ([JSONObject isKindOfClass:[NSDictionary class]]){
        NSMutableDictionary *mutableDictionary = [NSMutableDictionary dictionaryWithDictionary:JSONObject];
        for (id <NSCopying> key in [(NSDictionary *)JSONObject allKeys]) {
            id value = (NSDictionary *)JSONObject[key];
            if (!value || [value isEqual:[NSNull null]]) {
                [mutableDictionary removeObjectForKey:key];
            } else if ([value isKindOfClass:[NSArray class]] || [value isKindOfClass:[NSDictionary class]]){
                mutableDictionary[key] = ZCJSONObjectByRemovingKeysWithNullValues(value, readingOptions);
            }
        }
        
        return (readingOptions & NSJSONReadingMutableContainers) ? mutableDictionary : [NSDictionary dictionaryWithDictionary:mutableDictionary];
    }
    
    return JSONObject;
}

@implementation ZCHTTPResponseSerializer

+ (instancetype)serializer{
    return [[self alloc] init];
}

- (instancetype)init{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.acceptableStatusCodes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];
    self.acceptableContentTypes = nil;
    
    return self;
}

#pragma mark - 

- (BOOL)validateResponse:(NSHTTPURLResponse *)response
                    data:(NSData *)data
                   error:(NSError *__autoreleasing  _Nullable *)error{
    BOOL responseIsValid = YES;
    NSError *validationError = nil;
    
    if (response && [response isKindOfClass:[NSHTTPURLResponse class]]) {
        if (self.acceptableContentTypes && ![self.acceptableContentTypes containsObject:[response MIMEType]] && !([response MIMEType] == nil && [data length] == 0)) {
            if ([data length] > 0 && [response URL]) {
                NSMutableDictionary *mutableUserInfo = [@{NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedStringFromTable(@"Request failed: unacceptable content-type: %@", @"ZCNetworking", nil), [response MIMEType]],
                                                          NSURLErrorFailingURLErrorKey: [response URL], ZCNetworkingOperationFailingURLResponseErrorKey: response} mutableCopy];
                if (data) {
                    mutableUserInfo[ZCNetworkingOperationFailingURLResponseDataErrorKey] = data;
                }
                
                validationError = ZCErrorWithUnderlyingError([NSError errorWithDomain:ZCURLResponseSerializationErrorDomain code:NSURLErrorCannotDecodeContentData userInfo:mutableUserInfo], validationError);
            }
            
            responseIsValid = NO;
        }
        
        if (self.acceptableStatusCodes && ![self.acceptableStatusCodes containsIndex:(NSUInteger)response.statusCode] && [response URL]) {
            NSMutableDictionary *mutableUserInfo = [@{NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedStringFromTable(@"Request faildL %@ (%ld)", @"ZCNetworking", nil), [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode],(long)response.statusCode],NSURLErrorFailingURLErrorKey:[response URL], ZCNetworkingOperationFailingURLResponseErrorKey: response } mutableCopy];
            
            if (data) {
                mutableUserInfo[ZCNetworkingOperationFailingURLResponseErrorKey] = data;
            }
            
            validationError = ZCErrorWithUnderlyingError([NSError errorWithDomain:ZCURLResponseSerializationErrorDomain code:NSURLErrorBadServerResponse userInfo:mutableUserInfo], validationError);
            
            responseIsValid = NO;
            
        }
    }
    
    if (error && !responseIsValid) {
        *error = validationError;
    }
    
    return responseIsValid;
}

#pragma mark - ZCURLResponseSerialization

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing  _Nullable *)error{
    [self validateResponse:(NSHTTPURLResponse *)response data:data error:error];
    return  data;
}


#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [self init];
    if (!self) {
        return  nil;
    }
    
    self.acceptableStatusCodes = [aDecoder decodeObjectOfClass:[NSIndexSet class] forKey:NSStringFromSelector(@selector(acceptableStatusCodes))];
    self.acceptableContentTypes = [aDecoder decodeObjectOfClass:[NSIndexSet class] forKey:NSStringFromSelector(@selector(acceptableContentTypes))];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.acceptableStatusCodes forKey:NSStringFromSelector(@selector(acceptableStatusCodes))];
    [aCoder encodeObject:self.acceptableContentTypes forKey:NSStringFromSelector(@selector(acceptableContentTypes))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone{
    ZCHTTPResponseSerializer *serializer = [[[self class] allocWithZone:zone] init];
    serializer.acceptableStatusCodes = [serializer.acceptableStatusCodes copyWithZone:zone];
    serializer.acceptableContentTypes = [serializer.acceptableContentTypes copyWithZone:zone];
    
    return serializer;
}

@end

#pragma mark - 

@implementation ZCJSONResponseSerializer

+ (instancetype)serializer{
    return [self serializerWithReadingOptions:(NSJSONReadingOptions)0];
}

+ (instancetype)serializerWithReadingOptions:(NSJSONReadingOptions)readingOptions{
    ZCJSONResponseSerializer *serializer = [[self alloc] init];
    serializer.readingOptions = readingOptions;
    
    return serializer;
}

- (instancetype)init{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.acceptableContentTypes = [NSSet setWithObjects:@"application/json", @"text/json", @"text/javascript", nil];
    
    return self;
}

#pragma mark - ZCURLResponseSerialization

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing  _Nullable *)error{
    if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        if (!error || ZCErrorOrUnderlyingErrorHasCodeInDomain(*error, NSURLErrorCannotDecodeRawData, ZCURLResponseSerializerErrorDomain)) {
            return nil;
            
        }
    }
    
    BOOL isSpace = [data isEqualToData:[NSData dataWithBytes:@" " length:1]];
    if (data.length == 0 || isSpace) {
        return nil;
    }
    
    NSError *serializationError = nil;
    
    id responseObject = [NSJSONSerialization JSONObjectWithData:data options:self.readingOptions error:&serializationError];
    if (!responseObject) {
        if (error) {
            *error = ZCErrorWithUnderlyingError(serializationError, *error);
        }
        
        return nil;
    }
    
    if (self.removesKeysWithNullValues) {
        return ZCJSONObjectByRemovingKeysWithNullValues(responseObject, self.readingOptions);
    }
    
    return responseObject;
}

#pragma mark - NSSecureCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
    self.readingOptions = [[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(readingOptions))] unsignedIntegerValue];
    self.removesKeysWithNullValues = [[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(removesKeysWithNullValues))] boolValue];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [super encodeWithCoder:aCoder];
    
    [aCoder encodeObject:@(self.readingOptions) forKey:NSStringFromSelector(@selector(readingOptions))];
    [aCoder encodeObject:@(self.removesKeysWithNullValues) forKey:NSStringFromSelector(@selector(removesKeysWithNullValues))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone{
    ZCJSONResponseSerializer *serializer = [super copyWithZone:zone];
    self.readingOptions = self.readingOptions;
    serializer.removesKeysWithNullValues = self.removesKeysWithNullValues;
    
    return serializer;
}

@end

#pragma mark - 

@implementation ZCXMLParserResponseSerializer

+ (instancetype)serializer{
    return  [[self alloc] init];
}

- (instancetype)init{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.acceptableContentTypes = [[NSSet alloc] initWithObjects:@"applicaiton/xml", @"text/xml",nil];
    
    return self;
}

#pragma mark - ZCURLResponseSerialization

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing  _Nullable *)error{
    if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        if (!error || ZCErrorOrUnderlyingErrorHasCodeInDomain(*error, NSURLErrorCannotDecodeContentData, ZCURLResponseSerializationErrorDomain)) {
            return nil;
        }
    }
    
    return [[NSXMLParser alloc] initWithData:data];
}

@end

#pragma mark - 

#ifdef  __MAC_OS_X_VERSION_MIN_REQUIRED

@implementation ZCXMLDocumentrResponseSerializer

+ (instancetype)serializer{
    return [self serializerWithXMLDocumentOptions:0];
}

+ (instancetype)serializerWithXMLDocumentOptions:(NSUInteger)mask{
    ZCXMLDocumentrResponseSerializer *serializer = [[self alloc] init];
    serializer.options = mask;
    
    return serializer;
}

- (instancetype)init{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.acceptableContentTypes = [[NSSet alloc] initWithObjects:@"applicaiton/xml", @"text/xml",nil];
    return self;
}

#pragma mark - ZCURLResponseSerializaton

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing  _Nullable *)error{
    if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        if (!error || ZCErrorOrUnderlyingErrorHasCodeInDomain(*error, NSURLErrorCannotDecodeContentData, ZCURLResponseSerializationErrorDomain)) {
            return nil;
        }
    }
    
    NSError *serializationError = nil;
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:self.options error:&serializationError];
    if (!document)
    {
        if (error) {
            *error = AFErrorWithUnderlyingError(serializationError, *error);
        }
        return nil;
    }
    
    return document;
}

#pragma mark - NSSecureCoding

- (instancetype)initWithCoder:(NSCoder *)decoder {
    self = [super initWithCoder:decoder];
    if (!self) {
        return nil;
    }
    
    self.options = [[decoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(options))] unsignedIntegerValue];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    
    [coder encodeObject:@(self.options) forKey:NSStringFromSelector(@selector(options))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    AFXMLDocumentResponseSerializer *serializer = [super copyWithZone:zone];
    serializer.options = self.options;
    
    return serializer;
}

@end

#endif

#pragma mark - 

@implementation ZCPropertyListResponseSerializer

+ (instancetype)serializer{
    return [self serializerWithFormat:NSPropertyListXMLFormat_v1_0 readOptions:0];
}

+ (instancetype)serializerWithFormat:(NSPropertyListFormat)format
                         readOptions:(NSPropertyListReadOptions)readOptions{
    ZCPropertyListResponseSerializer *serializer = [[self alloc] init];
    serializer.format = format;
    serializer.readOptions = readOptions;
    
    return serializer;
}

- (instancetype)init{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.acceptableContentTypes = [[NSSet alloc] initWithObjects:@"application/x-plist", nil];
    
    return self;
}

#pragma mark - ZCURLResponseSerialization

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing  _Nullable *)error{
    if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        if (!error || ZCErrorOrUnderlyingErrorHasCodeInDomain(*error, NSURLErrorCannotDecodeContentData, ZCURLResponseSerializationErrorDomain)) {
            return nil;
        }
    }
    
    if (!data) {
        return nil;
    }
    
    NSError *serializationError = nil;
    
    id responseObject = [NSPropertyListSerialization propertyListWithData:data options:self.readOptions format:NULL error:&serializationError];
    
    if (!responseObject) {
        if (error) {
            *error = ZCErrorWithUnderlyingError(serializationError, *error);
        }
        return nil;
    }
    
    return responseObject;
}

#pragma mark - NSSecureCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
    self.format = (NSPropertyListFormat)[[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(format))] unsignedIntegerValue];
    self.readOptions = [[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(readOptions))] unsignedIntegerValue];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [super encodeWithCoder:aCoder];
    
    [aCoder encodeObject:@(self.format) forKey:NSStringFromSelector(@selector(format))];
    [aCoder encodeObject:@(self.readOptions) forKey:NSStringFromSelector(@selector(readOptions))];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone{
    ZCPropertyListResponseSerializer *serializer = [super copyWithZone:zone];
    serializer.format = self.format;
    serializer.readOptions = self.readOptions;
    
    return serializer;
}

@end

#pragma mark - 

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

@interface UIImage (ZCNetworkingSafeImageLoading)
+ (UIImage *)zc_safeImageWithData:(NSData *)data;
@end

static NSLock *imageLock = nil;

@implementation UIImage (ZCImageResponseSerializer)

+ (UIImage *)zc_safeImageWithData:(NSData *)data{
    UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageLock = [[NSLock alloc] init];
    });
    
    [imageLock lock];
    image = [UIImage imageWithData:data];
    [imageLock unlock];
    return image;
}

@end

static UIImage * ZCImageWithDataAtScale(NSData *data, CGFloat scale){
    UIImage *image = [UIImage zc_safeImageWithData:data];
    if (image.images) {
        return image;
    }
    
    return [[UIImage alloc] initWithCGImage:[image CGImage] scale:scale orientation:image.imageOrientation];
}

static UIImage * ZCInflatedImageFromResponseWithDataScale(NSHTTPURLResponse *response, NSData *data, CGFloat scale){
    if (!data || [data length] == 0) {
        return nil;
    }
    
    CGImageRef imageRef = NULL;
    CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    if ([response.MIMEType isEqualToString:@"image/png"]) {
        imageRef = CGImageCreateWithPNGDataProvider(dataProvider, NULL, true, kCGRenderingIntentDefault);
    } else if ([response.MIMEType isEqualToString:@"image/jpeg"]){
        imageRef = CGImageCreateWithJPEGDataProvider(dataProvider, NULL, true, kCGRenderingIntentDefault);
        
        if (imageRef) {
            CGColorSpaceRef imageColorSpace = CGImageGetColorSpace(imageRef);
            CGColorSpaceModel imageColorSpaceModel = CGColorSpaceGetModel(imageColorSpace);
            
            if (imageColorSpaceModel == kCGColorSpaceModelCMYK) {
                CGImageRelease(imageRef);
                imageRef = NULL;
            }
        }
    }
    
    CGDataProviderRelease(dataProvider);
    
    UIImage *image = ZCImageWithDataAtScale(data, scale);
    if (!imageRef) {
        if (image.images || !image) {
            return image;
        }
        
        imageRef = CGImageCreateCopy([image CGImage]);
        if (!imageRef) {
            return nil;
        }
    }
    
    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    size_t bitsPerComponent = CGImageGetBitsPerComponent(imageRef);
    
    if (width * height > 1024 * 1024 || bitsPerComponent > 8) {
        CGImageRelease(imageRef);
        
        return image;
    }
    
    size_t bytesPerRow = 0;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGColorSpaceModel colorSpaceModel = CGColorSpaceGetModel(colorSpace);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);
    
    if (colorSpaceModel == kCGColorSpaceModelRGB) {
        uint32_t alpha = (bitmapInfo & kCGBitmapAlphaInfoMask);
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
        if (alpha == kCGImageAlphaNone) {
            bitmapInfo &= ~kCGBitmapAlphaInfoMask;
            bitmapInfo |= kCGImageAlphaNoneSkipFirst;
        } else if (!(alpha == kCGImageAlphaNoneSkipFirst || alpha == kCGImageAlphaNoneSkipLast)){
            bitmapInfo &= ~kCGBitmapAlphaInfoMask;
            bitmapInfo |= kCGImageAlphaPremultipliedFirst;
        }
#pragma clang diagnostic pop
    }
    
    CGContextRef context  = CGBitmapContextCreate(NULL, width, height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
    
    CGColorSpaceRelease(colorSpace);
    
    if (!context) {
        CGImageRelease(imageRef);
        
        return image;
    }
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGImageRef inflatedImageRef = CGBitmapContextCreateImage(context);
    
    CGContextRelease(context);
    
    UIImage *inflatedImage = [[UIImage alloc] initWithCGImage:inflatedImageRef scale:scale orientation:image.imageOrientation];
    
    CGImageRelease(inflatedImageRef);
    CGImageRelease(imageRef);
    
    return inflatedImage;
}
#endif

@implementation ZCImageResponseSerializer

- (instancetype)init{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.acceptableContentTypes = [[NSSet alloc] initWithObjects:@"image/tiff", @"image/jpeg", @"image/gif", @"image/png", @"image/ico", @"image/x-icon", @"image/bmp", @"image/x-bmp", @"image/x-xbitmap", @"image/x-win-bitmap", nil];
    self.imageScale = [[UIScreen mainScreen] scale];
    self.automaticallyInflatesResponseImage = YES;
    
    return self;
}

#pragma mark - ZCURLResponseSerializer

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing  _Nullable *)error{
    if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
        if (!error || ZCErrorOrUnderlyingErrorHasCodeInDomain(*error, NSURLErrorCannotDecodeContentData, ZCURLResponseSerializationErrorDomain)) {
            return nil;
        }
    }
    
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH
    if (self.automaticallyInflatesResponseImage) {
        return ZCInflatedImageFromResponseWithDataScale((NSHTTPURLResponse *)response, data, self.imageScale);
    } else {
        return ZCImageWithDataAtScale(data, self.imageScale);
    }
#endif
    return nil;
}

#pragma mark - NSSecureCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
#if TARGET_OS_IOS || TAGET_OS_TV || TARGET_OS_WATCH
    NSNumber *imageScale = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(imageScale))];
#if CGFLOAT_IS_DOUBLE
    self.imageScale = [imageScale doubleValue];
#else
    self.imageScale = [imageScale floatValue];
#endif
    self.automaticallyInflatesResponseImage = [aDecoder decodeBoolForKey:NSStringFromSelector(@selector(automaticallyInflatesResponseImage))];
#endif
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [super encodeWithCoder:aCoder];
    
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH
    [aCoder encodeObject:@(self.imageScale) forKey:NSStringFromSelector(@selector(imageScale))];
    [aCoder encodeBool:self.automaticallyInflatesResponseImage forKey:NSStringFromSelector(@selector(automaticallyInflatesResponseImage))];
#endif
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone{
    ZCImageResponseSerializer *serializer = [super copyWithZone:zone];
    
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH
    serializer.imageScale = self.imageScale;
    self.automaticallyInflatesResponseImage = self.automaticallyInflatesResponseImage;
#endif
    
    return serializer;
}
@end

#pragma mark - 

@interface ZCCompoundResponseSerializer ()
@property (readwrite, nonatomic, copy) NSArray * responseSerializers;
@end

@implementation ZCCompoundResponseSerializer

+ (instancetype)compoundSerailizerWithResponseSerializers:(NSArray<id<ZCURLResponseSerialization>> *)responseSerializers{
    ZCCompoundResponseSerializer *serializer = [[self alloc] init];
    serializer.responseSerializers = responseSerializers;
    
    return serializer;
}

#pragma mark - ZCURLReponseSerialization

- (id)responseObjectForResponse:(NSURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing  _Nullable *)error{
    for (id <ZCURLResponseSerialization> serializer in self.responseSerializers) {
        if (![serializer isKindOfClass:[ZCHTTPResponseSerializer class]]) {
            continue;
        }
        
        NSError *serializerError = nil;
        id responseObject = [serializer responseObjectForResponse:response data:data error:&serializerError];
        if (responseObject) {
            if (error) {
                *error = ZCErrorWithUnderlyingError(serializerError, *error);
            }
            
            return responseObject;
        }
    }
    
    return [super responseObjectForResponse:response data:data error:error];
}

#pragma mark - NSSecureCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
    self.responseSerializers = [aDecoder decodeObjectOfClass:[NSArray class] forKey:NSStringFromSelector(@selector(responseSerializers))];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [super encodeWithCoder:aCoder];
    
    [aCoder encodeObject:self.responseSerializers forKey:NSStringFromSelector(@selector(responseSerializers))];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone{
    ZCCompoundResponseSerializer *serializer = [super copyWithZone:zone];
    serializer.responseSerializers = serializer.responseSerializers;
    
    return serializer;
}

@end
