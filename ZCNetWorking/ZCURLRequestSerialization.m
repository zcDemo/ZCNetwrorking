//
//  ZCURLRequestSerialization.m
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import "ZCURLRequestSerialization.h"

#if TARGET_OS_IOS || TAGRET_OS_WATCH || TARGET_OS_TV
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <CoreServices/CoreServices.h>
#endif

NSString * const ZCURLRequestSerializationErrorDomain = @"com.zc.error.serialization.requset";
NSString * const  ZCNetworkingOperationFailingURLRequsetErrorKey = @"com.zc.serailization.request.error.response";

typedef  NSString * (^ZCQueryStringSerializationBlock)(NSURLRequest *request, id parameters, NSError * __autoreleasing *error);

NSString * ZCPercentEscapedStringFromString(NSString *string) {
    static NSString * const kZCCharacterGeneralDelimitersToEncode = @":#[]@";
    static NSString * const kZCCharactersSubDelimitersToEncode  = @"!$&'()*+,;=";

    NSMutableCharacterSet *allowedCharacterSet = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowedCharacterSet removeCharactersInString:[kZCCharacterGeneralDelimitersToEncode stringByAppendingString:kZCCharactersSubDelimitersToEncode]];
    
    static NSUInteger const batchSize = 50;
    
    NSUInteger index = 0;
    NSMutableString *escaped = @"".mutableCopy;
    
    while (index < string.length) {
        NSUInteger lenght = MIN(string.length - index, batchSize);
        NSRange range = NSMakeRange(index, lenght);
        
        range = [string rangeOfComposedCharacterSequencesForRange:range];
        
        NSString *substring = [string substringWithRange:range];
        NSString *encoded = [substring stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];
        [escaped appendString:encoded];
        
        index += range.length;
    }
    
    return escaped;
}

#pragma mark - 

@interface ZCQueryStringPair : NSObject
@property (readwrite, nonatomic, strong) id field;
@property (readwrite, nonatomic, strong) id value;

- (instancetype)initWithField:(id)field value:(id)value;

- (NSString *)URLEncodedStringValue;

@end

@implementation ZCQueryStringPair

- (instancetype)initWithField:(id)field value:(id)value{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.field = field;
    self.value = value;
    
    return self;
}


- (NSString *)URLEncodedStringValue{
    if (!self.value || [self.value isEqual:[NSNull null]]) {
        return ZCPercentEscapedStringFromString([self.field description]);
    } else {
        return [NSString stringWithFormat:@"%@=%@", ZCPercentEscapedStringFromString([self.field description]), ZCPercentEscapedStringFromString([self.value description])];
    }
}

@end

#pragma mark - 

FOUNDATION_EXPORT NSArray * ZCQueryStringPairsFromDictionary(NSDictionary *dictionary);
FOUNDATION_EXPORT NSArray * ZCQueryStringPairsFromKeyAndValue(NSString *key, id value);

NSString * ZCQueryStringFromParameters(NSDictionary *parameters){
    NSMutableArray *mutablePairs = [NSMutableArray array];
    for (ZCQueryStringPair *pair in ZCQueryStringPairsFromDictionary(parameters)) {
        [mutablePairs addObject:[pair URLEncodedStringValue]];
    }
    
    return [mutablePairs componentsJoinedByString:@"&"];
}

NSArray * ZCQueryStringPairsFromDictionary(NSDictionary *dictionary){
    return ZCQueryStringPairsFromKeyAndValue(nil, dictionary);
}

NSArray * ZCQueryStringPairsFromKeyAndValue(NSString *key, id value){
    NSMutableArray *mutableQueryStringComponents = [NSMutableArray array];
    
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"description" ascending:YES selector:@selector(compare:)];
    
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = value;
        for (id nestedKey in [dictionary.allKeys sortedArrayUsingDescriptors:@[sortDescriptor]]) {
            id nestedValue = dictionary[nestedKey];
            if (nestedValue) {
                [mutableQueryStringComponents addObjectsFromArray:ZCQueryStringPairsFromKeyAndValue((key ? [NSString stringWithFormat:@"%@[%@]", key, nestedKey] : nestedKey), nestedValue)];
            }
        }
    } else if ([value isKindOfClass:[NSArray class]]){
        NSArray *array = value;
        for (id nestedValue in array) {
            [mutableQueryStringComponents addObjectsFromArray:ZCQueryStringPairsFromKeyAndValue([NSString stringWithFormat:@"%@[]", key], nestedValue)];
        }
    } else if ([value isKindOfClass:[NSSet class]]){
        NSSet *set = value;
        for (id obj in [set sortedArrayUsingDescriptors:@[sortDescriptor]]) {
            [mutableQueryStringComponents addObjectsFromArray:ZCQueryStringPairsFromKeyAndValue(key, obj)];
        }
    } else {
        [mutableQueryStringComponents addObject:[[ZCQueryStringPair alloc] initWithField:key value:value]];
    }
    
    return mutableQueryStringComponents;
}

#pragma mark -

@interface ZCStreamingMultipartFormData : NSObject <ZCMultipartFormData>

- (instancetype)initWithURLRequest:(NSMutableURLRequest *)URLRequest stringEncoding:(NSStringEncoding)encoding;

- (NSMutableURLRequest *)requestByFinalizingMultipartFormData;
@end

#pragma mark -

static NSArray * ZCHTTPRequestSerializerObservedKeyPaths() {
    static NSArray *_ZCHTTPRequestSerializerObservedKeyPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _ZCHTTPRequestSerializerObservedKeyPaths = @[NSStringFromSelector(@selector(allowsCellularAccess)), NSStringFromSelector(@selector(cachePolicy)), NSStringFromSelector(@selector(HTTPShouldSetCookies)), NSStringFromSelector(@selector(networkServiceType)), NSStringFromSelector(@selector(timeoutInterval))];
    });
    
    return _ZCHTTPRequestSerializerObservedKeyPaths;
}

static void *ZCHTTPRequestSerializerObserverContext = &ZCHTTPRequestSerializerObserverContext;

@interface ZCHTTPRequestSerializer ()
@property (readwrite, nonatomic, strong) NSMutableSet *mutableObservedChangedKeyPaths;
@property (readwrite, nonatomic, strong) NSMutableDictionary *mutableHTTPRequestHeaders;
@property (readwrite, nonatomic, strong) dispatch_queue_t requestHeaderModificationQueue;
@property (readwrite, nonatomic, assign) ZCHTTPRequestQueryStringSerialzationStyle queryStringSerializationStyle;
@property (readwrite, nonatomic, copy) ZCQueryStringSerializationBlock queryStringSerialization;

@end

@implementation ZCHTTPRequestSerializer

+ (instancetype)serializer{
    return [[self alloc] init];
}


- (instancetype)init{
    self = [super init];
    if (!self) {
        return  nil;
    }
    
    self.stringEncoding = NSUTF8StringEncoding;
    
    self.mutableHTTPRequestHeaders = [NSMutableDictionary dictionary];
    self.requestHeaderModificationQueue = dispatch_queue_create("requestHeaderModificationQueue", DISPATCH_QUEUE_CONCURRENT);
    
    NSMutableArray *accpetLanguagesComponents = [NSMutableArray array];
    [[NSLocale preferredLanguages] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL * _Nonnull stop) {
        float q = 1.0f - (idx * 0.1f);
        [accpetLanguagesComponents addObject:[NSString stringWithFormat:@"%@;q=%0.1g",obj, q]];
        *stop = q <= 0.5f;
    }];
    [self setValue:[accpetLanguagesComponents componentsJoinedByString:@", "] forHTTPHeaderField:@"Accept-Language"];
    
    NSString *userAgent = nil;
#if  TARGET_OS_IOS
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; iOS %@; Scale/%0.2f)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[UIDevice currentDevice] model], [[UIDevice currentDevice] systemVersion], [[UIScreen mainScreen] scale]];
#elif TARGET_OS_WATCH
    // User-Agent Header; see http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.43
    userAgent = [NSString stringWithFormat:@"%@/%@ (%@; watchOS %@; Scale/%0.2f)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[WKInterfaceDevice currentDevice] model], [[WKInterfaceDevice currentDevice] systemVersion], [[WKInterfaceDevice currentDevice] screenScale]];
#elif defined(__MAC_OS_X_VERSION_MIN_REQUIRED)
    userAgent = [NSString stringWithFormat:@"%@/%@ (Mac OS X %@)", [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleExecutableKey] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleIdentifierKey], [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"] ?: [[NSBundle mainBundle] infoDictionary][(__bridge NSString *)kCFBundleVersionKey], [[NSProcessInfo processInfo] operatingSystemVersionString]];
#endif
    if (userAgent) {
        if (![userAgent canBeConvertedToEncoding:NSASCIIStringEncoding]) {
            NSMutableString *mutableUserAgent = [userAgent mutableCopy];
            if (CFStringTransform((__bridge_retained CFMutableStringRef)(mutableUserAgent), NULL, (__bridge CFStringRef)@"Any-Latinl Latin-ASCII; [:^ASCII:] Remove", false)) {
                userAgent  = mutableUserAgent;
            }
        }
        [self setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    
    self.HTTPMethodsEncodingParametersInURI = [NSSet setWithObjects:@"GET", @"HEAD", @"DELETE", nil];
    
    self.mutableObservedChangedKeyPaths = [NSMutableSet set];
    for (NSString *keyPath in ZCHTTPRequestSerializerObservedKeyPaths()) {
        if ([self respondsToSelector:NSSelectorFromString(keyPath)]) {
            [self addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:ZCHTTPRequestSerializerObserverContext];
        }
    }
    
    return self;
}

- (void)dealloc{
    for (NSString *keyPath in ZCHTTPRequestSerializerObservedKeyPaths()) {
        if ([self respondsToSelector:NSSelectorFromString(keyPath)]) {
            [self removeObserver:self forKeyPath:keyPath context:ZCHTTPRequestSerializerObserverContext];
        }
    }
}

#pragma mark - 

- (void)setAllowsCellularAccess:(BOOL)allowsCellularAccess{
    [self willChangeValueForKey:NSStringFromSelector(@selector(allowsCellularAccess))];
    _allowsCellularAccess = allowsCellularAccess;
    [self didChangeValueForKey:NSStringFromSelector(@selector(allowsCellularAccess))];
}

- (void)setCachePolicy:(NSURLRequestCachePolicy)cachePolicy{
    [self willChangeValueForKey:NSStringFromSelector(@selector(cachePolicy))];
    _cachePolicy = cachePolicy;
    [self didChangeValueForKey:NSStringFromSelector(@selector(cachePolicy))];
}

-  (void)setHTTPShouldHandleCookies:(BOOL)HTTPShouldHandleCookies{
    [self willChangeValueForKey:NSStringFromSelector(@selector(HTTPShouldSetCookies))];
    _HTTPShouldHandleCookies = HTTPShouldHandleCookies;
    [self didChangeValueForKey:NSStringFromSelector(@
     selector(HTTPShouldSetCookies))];
}

- (void)setHTTPShouldUsePipeling:(BOOL)HTTPShouldUsePipeling{
    [self willChangeValueForKey:NSStringFromSelector(@selector(HTTPShouldUsePipeling))];
    _HTTPShouldUsePipeling = HTTPShouldUsePipeling;
    [self didChangeValueForKey:NSStringFromSelector(@selector(HTTPShouldUsePipeling))];
}

- (void)setNetworkServiceType:(NSURLRequestNetworkServiceType)networkServiceType{
    [self willChangeValueForKey:NSStringFromSelector(@selector(networkServiceType))];
    _networkServiceType = networkServiceType;
    [self didChangeValueForKey:NSStringFromSelector(@selector(networkServiceType))];
}

- (void)setTimeoutInterval:(NSTimeInterval)timeoutInterval{
    [self willChangeValueForKey:NSStringFromSelector(@selector(timeoutInterval))];
    _timeoutInterval = timeoutInterval;
    [self didChangeValueForKey:NSStringFromSelector(@selector(timeoutInterval))];
}

#pragma mark -

- (NSDictionary *)HTTPRequestHeaders{
    NSDictionary __block *value;
    dispatch_sync(self.requestHeaderModificationQueue, ^{
        value = [NSDictionary dictionaryWithDictionary:self.mutableHTTPRequestHeaders];
    });
    return value;
}

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field{
    dispatch_barrier_sync(self.requestHeaderModificationQueue, ^{
        [self.mutableHTTPRequestHeaders setValue:value forKey:field];
    });
}

- (NSString *)valueForHTTPHeaderField:(NSString *)field{
    NSString __block *value;
    dispatch_sync(self.requestHeaderModificationQueue, ^{
        value = [self.mutableHTTPRequestHeaders valueForKey:field];
    });
    return value;
}

- (void)setAuthonrizationHeaderFieldWithUsername:(NSString *)username
                                        password:(NSString *)password{

    NSData *basicAuthCredentials = [[NSString stringWithFormat:@"%@:%@", username, password] dataUsingEncoding:NSUTF8StringEncoding];
    NSString *base64AuthCredentials = [basicAuthCredentials base64EncodedStringWithOptions:(NSDataBase64EncodingOptions)0];
    [self setValue:[NSString stringWithFormat:@"Basic %@", base64AuthCredentials] forHTTPHeaderField:@"Authorization"];
}

- (void)clearAuthorizationHeader{
    dispatch_barrier_async(self.requestHeaderModificationQueue, ^{
        [self.mutableHTTPRequestHeaders removeObjectForKey:@"Authorization"];
    });
}

#pragma mark - 

- (void)setQueryStringSerializationWithStyle:(ZCHTTPRequestQueryStringSerialzationStyle)style{
    self.queryStringSerializationStyle = style;
    self.queryStringSerialization = nil;
}

- (void)setQueryStringSerializationWithBlock:(NSString * _Nonnull (^)(NSURLRequest * _Nonnull, id _Nonnull, NSError * _Nullable __autoreleasing * _Nullable))block{
    self.queryStringSerialization = block;
}

#pragma mark -

- (NSMutableURLRequest *)requstWithMethod:(NSString *)method
                                URLString:(NSString *)URLString
                               parameters:(id)parameters
                                    error:(NSError *__autoreleasing  _Nullable *)error{
    NSParameterAssert(method);
    NSParameterAssert(URLString);
    
    NSURL *url = [NSURL URLWithString:URLString];
    
    NSParameterAssert(url);
    
    NSMutableURLRequest *mutableRequest = [[NSMutableURLRequest alloc] initWithURL:url];
    mutableRequest.HTTPMethod = method;
    
    for (NSString *keyPath in ZCHTTPRequestSerializerObservedKeyPaths()) {
        if ([self.mutableObservedChangedKeyPaths containsObject:keyPath]) {
            [mutableRequest setValue:[self valueForKeyPath:keyPath] forKeyPath:keyPath];
        }
    }
    
    mutableRequest = [[self requestBySerializingRequest:mutableRequest withParameters:parameters error:error] mutableCopy];
    
    return mutableRequest;
}

- (NSMutableURLRequest *)multipartFormRequsetWithMethod:(NSString *)method
                                              URLString:(NSString *)URLString
                                             parameters:(NSDictionary<NSString *,id> *)parameters
                              constructionBodyWithBlock:(void (^)(id<ZCMultipartFormData> _Nonnull))block
                                                  error:(NSError *__autoreleasing  _Nullable *)error{
    NSParameterAssert(method);
    NSParameterAssert(![method isEqualToString:@"GET"] && ![method isEqualToString:@"HEAD"]);
    
    NSMutableURLRequest *mutableRequest = [self requstWithMethod:method URLString:URLString parameters:nil error:error];
    
    __block ZCStreamingMultipartFormData *formData = [[ZCStreamingMultipartFormData alloc] initWithURLRequest:mutableRequest stringEncoding:NSUTF8StringEncoding];
    
    if (parameters) {
        for (ZCQueryStringPair *pari in ZCQueryStringPairsFromDictionary(parameters)) {
            NSData *data = nil;
            if ([pari.value isKindOfClass:[NSData class]]) {
                data = pari.value;
            } else if ([pari.value isEqual:[NSNull null]]){
                data = [[pari.value description] dataUsingEncoding:self.stringEncoding];
            }
            
            if (data) {
                [formData appendPartWithFromData:data name:[pari.field description]];
            }
        }
    }
    
    if (block) {
        block(formData);
    }
    
    return [formData requestByFinalizingMultipartFormData];
    
}

- (NSMutableURLRequest *)requestWithMultipartFormRequest:(NSURLRequest *)request
                             writingStreamContentsToFile:(NSURL *)fileUR
                                       completionHandler:(void (^)(NSError * _Nullable))handler{
    NSParameterAssert(request.HTTPBodyStream);
    NSParameterAssert([fileUR isFileURL]);
    
    NSInputStream *inputStream = request.HTTPBodyStream;
    NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:fileUR append:NO];
    __block NSError *error = nil;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        
        [inputStream open];
        [outputStream open];
        
        while ([inputStream hasBytesAvailable] && [outputStream hasSpaceAvailable]) {
            uint8_t buffer[1024];
            
            NSInteger bytesRead = [inputStream read:buffer maxLength:1024];
            if (inputStream.streamError || bytesRead < 0) {
                error = inputStream.streamError;
                break;
            }
            
            NSInteger bytesWritten = [outputStream write:buffer maxLength:(NSUInteger)bytesRead];
            if (outputStream.streamError || bytesWritten < 0) {
                error = outputStream.streamError;
                break;
            }
            
            if (bytesRead == 0 && bytesWritten == 0) {
                break;
            }
        }
        
        [outputStream close];
        [inputStream close];
        
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler(error);
            });
        }
    });
            
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    mutableRequest.HTTPBodyStream = nil;
    
    return mutableRequest;
}

#pragma mark - ZCURLRequestSerialization

- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing  _Nullable *)error{
    NSParameterAssert(request);
    
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    
    [self.HTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * _Nonnull stop) {
        if (![request valueForHTTPHeaderField:field]) {
            [mutableRequest setValue:value forHTTPHeaderField:field];
        }
    }];
    
    NSString *query = nil;
    if (parameters) {
        if (self.queryStringSerialization) {
            NSError *serializationError;
            query = self.queryStringSerialization(request, parameters, &serializationError);
            
            if (serializationError) {
                if (error) {
                    *error = serializationError;
                }
                
                return nil;
            }
        } else {
            switch (self.queryStringSerializationStyle) {
                case ZCHTTPRequestQueryStringDefaultStyle:
                    query = ZCQueryStringFromParameters(parameters);
                    break;
            }
        }
    }
    
    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[[request HTTPMethod] uppercaseString]]) {
        if (query && query.length > 0) {
            mutableRequest.URL = [NSURL URLWithString:[[mutableRequest.URL absoluteString] stringByAppendingFormat:mutableRequest.URL.query ? @"&%@" : @"?%@", query]];
        }
    } else {
        if (!query) {
            query = @"";
        }
        
        if (![mutableRequest valueForHTTPHeaderField:@"Content-Type"]) {
            [mutableRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
        }
        [mutableRequest setHTTPBody:[query dataUsingEncoding:self.stringEncoding]];
    }
    
    return  mutableRequest;
}

#pragma  mark - NSKeyValueObsrving

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key{
    if ([ZCHTTPRequestSerializerObservedKeyPaths() containsObject:key]) {
        return NO;
    }
    
    return [super automaticallyNotifiesObserversForKey:key];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context{
    if (context == ZCHTTPRequestSerializerObserverContext) {
        if ([change[NSKeyValueChangeNewKey] isEqual:[NSNull null]]) {
            [self.mutableObservedChangedKeyPaths removeObject:keyPath];
        } else {
            [self.mutableObservedChangedKeyPaths addObject:keyPath];
        }
    }
}


#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    if (!self) {
        return  nil;
    }
    
    self.mutableObservedChangedKeyPaths =[aDecoder decodeObjectOfClass:[NSDictionary class] forKey:[NSStringFromSelector(@selector(mutableHTTPRequestHeaders)) mutableCopy]];
    self.queryStringSerializationStyle = (ZCHTTPRequestQueryStringSerialzationStyle)[[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(queryStringSerializationStyle))] unsignedIntegerValue];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    dispatch_sync(self.requestHeaderModificationQueue, ^{
        [aCoder encodeObject:self.mutableHTTPRequestHeaders forKey:NSStringFromSelector(@selector(mutableHTTPRequestHeaders))];
    });
    [aCoder encodeInteger:self.queryStringSerializationStyle forKey:NSStringFromSelector(@selector(queryStringSerializationStyle))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone{
    ZCHTTPRequestSerializer *serializer = [[[self class] allocWithZone:zone] init];
    dispatch_sync(self.requestHeaderModificationQueue, ^{
        serializer.mutableHTTPRequestHeaders = [self.mutableHTTPRequestHeaders mutableCopyWithZone:zone];
    });
    serializer.queryStringSerializationStyle = self.queryStringSerializationStyle;
    serializer.queryStringSerialization = self.queryStringSerialization;
    
    return serializer;
}
@end

#pragma mark -

static NSString * ZCCreateMultipartFormBoundary(){
    return [NSString stringWithFormat:@"Boundary+%08X%08X", arc4random(), arc4random()];
}

static NSString * const kZCMultipartFormCRLF = @"\r\n";

static inline NSString * ZCMultipartFormInitialBoundary(NSString *boundary){
    return [NSString stringWithFormat:@"--%@%@", boundary, kZCMultipartFormCRLF];
}

static inline NSString * ZCMultipartFormEncapsulationBoundary(NSString *boundary){
    return [NSString stringWithFormat:@"%@--%@%@", kZCMultipartFormCRLF, boundary, kZCMultipartFormCRLF];
}


static inline NSString * ZCMultipartFormFinalBoundary(NSString * boundary){
    return [NSString stringWithFormat:@"%@--%@--%@", kZCMultipartFormCRLF, boundary, kZCMultipartFormCRLF];
}

static inline NSString * ZCContentTypeForPathExtension(NSString     *extension){
    NSString *UTI = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
    NSString *contentType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)UTI, kUTTagClassMIMEType);
    if (!contentType) {
        return @"application/octet-stream";
    } else {
        return contentType;
    }
}

NSUInteger const kZCUploadStream3GSuggestedPackedtSize = 1024 * 16;
NSTimeInterval const kZCUploadStream3GSuggestedDelay = 0.2;

@interface ZCHTTPBodyPart : NSObject
@property (nonatomic, assign) NSStringEncoding stringEncoding;
@property (nonatomic, strong) NSDictionary *headers;
@property (nonatomic, copy) NSString *boundary;
@property (nonatomic, strong) id body;
@property (nonatomic, assign) unsigned long long bodyContentLength;
@property (nonatomic, strong) NSInputStream *inputStream;

@property (nonatomic, assign) BOOL hasInitialBoundary;
@property (nonatomic, assign) BOOL hasFinalBoundary;

@property (readonly, nonatomic, assign, getter=hasBytesAvailable) BOOL bytesAvailable;
@property (readonly, nonatomic, assign) unsigned long long contentLength;

- (NSInteger)read:(uint8_t *)buffer maxLength:(NSUInteger)length;
@end

@interface ZCMultipartBodyStream : NSInputStream <NSStreamDelegate>
@property (nonatomic, assign) NSUInteger numberOfBytesInPacket;
@property (nonatomic, assign) NSTimeInterval delay;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (readonly, nonatomic, assign) unsigned long long contentLength;
@property (readonly, nonatomic, assign, getter=isEmpty) BOOL empty;

- (instancetype)initWithStringEncoding:(NSStringEncoding)encoding;
- (void)setInitialAndFinalBoundaries;
- (void)appendHTTPBodyPart:(ZCHTTPBodyPart *)bodyPart;
@end

#pragma mark - 

@interface ZCStreamingMultipartFormData ()
@property (readwrite, nonatomic, copy) NSMutableURLRequest *request;
@property (readwrite, nonatomic, assign) NSStringEncoding stringEncoding;
@property (readwrite, nonatomic, copy) NSString *boundary;
@property (readwrite, nonatomic, strong) ZCMultipartBodyStream *bodyStream;
@end

@implementation ZCStreamingMultipartFormData

- (instancetype)initWithURLRequest:(NSMutableURLRequest *)URLRequest
                    stringEncoding:(NSStringEncoding)encoding{
    self = [super init];
    if (!self) {
        return  nil;
    }
    
    self.request = URLRequest;
    self.stringEncoding = encoding;
    self.boundary = ZCCreateMultipartFormBoundary();
    self.bodyStream = [[ZCMultipartBodyStream alloc] initWithStringEncoding:encoding];
    
    return self;
}

- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                        error:(NSError *__autoreleasing  _Nullable *)error{
    NSParameterAssert(fileURL);
    NSParameterAssert(name);
    
    NSString *fileName = [fileURL lastPathComponent];
    NSString *mimeType = ZCContentTypeForPathExtension([fileURL pathExtension]);
    
    return [self appendPartWithFileURL:fileURL name:name fileName:fileName mineType:mimeType error:error];
}

- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                     fileName:(NSString *)fileName
                     mineType:(NSString *)mimeType
                        error:(NSError *__autoreleasing  _Nullable *)error{
    NSParameterAssert(fileURL);
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);
    
    if (![fileURL isFileURL]) {
        NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedStringFromTable(@"Expected URL to be a file URL", @"ZCNetworking", nil)};
        if (error) {
            *error = [[NSError alloc] initWithDomain:ZCURLRequestSerializationErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        
        return NO;
    } else if ([fileURL checkResourceIsReachableAndReturnError:error] == NO){
        NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedStringFromTable(@"FILE URL not reachable", @"ZCNetworking", nil)};
        if (error) {
            *error = [[NSError alloc] initWithDomain:ZCURLRequestSerializationErrorDomain code:NSURLErrorBadURL userInfo:userInfo];
        }
        return NO;
    }
    
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[fileURL path] error:error];
    if (!fileAttributes) {
        return  NO;
    }
    
    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileName] forKey:@"Content-Disposition"];
    [mutableHeaders setValue:mimeType forKey:@"Content-Type"];
    
    ZCHTTPBodyPart *bodyPart = [[ZCHTTPBodyPart alloc] init];
    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = mutableHeaders;
    bodyPart.boundary = self.boundary;
    bodyPart.body = fileURL;
    bodyPart.bodyContentLength = [fileAttributes[NSFileSize] unsignedLongLongValue];
    [self.bodyStream appendHTTPBodyPart:bodyPart];
    
    return YES;
}

- (BOOL)appendPartWithInputStream:(NSInputStream *)inputStream
                             name:(NSString *)name
                         fileName:(NSString *)fileName
                           length:(int64_t)length
                         mineType:(NSString *)mimeType{
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);
    
    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileName] forKey:@"Content-Disposition"];
    
    ZCHTTPBodyPart *bodyPart = [[ZCHTTPBodyPart alloc] init];
    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = mutableHeaders;
    bodyPart.boundary = self.boundary;
    bodyPart.body = inputStream;
    
    bodyPart.bodyContentLength = (unsigned long long)length;
    
    [self.bodyStream appendHTTPBodyPart:bodyPart];
    
    return nil;
}

- (void)appendPartWithFromData:(NSData *)data
                          name:(NSString *)name
                      fileName:(NSString *)fileName
                      mimeType:(NSString *)mimeType{
    NSParameterAssert(name);
    NSParameterAssert(fileName);
    NSParameterAssert(mimeType);
    
    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form-data; name=\"%@\"; filename=\"%@\"", name, fileName] forKey:@"Content-Disposition"];
    
    [self appendPartWithHeaders:mutableHeaders body:data];
}

- (void)appendPartWithFromData:(NSData *)data
                          name:(NSString *)name{
    NSParameterAssert(name);
    
    NSMutableDictionary *mutableHeaders = [NSMutableDictionary dictionary];
    [mutableHeaders setValue:[NSString stringWithFormat:@"form=data; name=\"%@\"", name] forKey:@"Content-Disposition"];
    
    [self appendPartWithHeaders:mutableHeaders body:data];
}

- (void)appendPartWithHeaders:(NSDictionary<NSString *,NSString *> *)headers
                         body:(NSData *)body{
    NSParameterAssert(body);
    
    ZCHTTPBodyPart *bodyPart = [[ZCHTTPBodyPart alloc] init];
    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = headers;
    bodyPart.boundary = self.boundary;
    bodyPart.bodyContentLength = [body length];
    bodyPart.body = body;
    
    [self.bodyStream appendHTTPBodyPart:bodyPart];
}

- (void)throttleBandwidthWithPacketSize:(NSUInteger)numberOfBytes
                                  delay:(NSTimeInterval)delay{
    self.bodyStream.numberOfBytesInPacket = numberOfBytes;
    self.bodyStream.delay = delay;
}

- (NSMutableURLRequest *)requestByFinalizingMultipartFormData{
    if ([self.bodyStream isEmpty]) {
        return self.request;
    }
    
    [self.bodyStream setInitialAndFinalBoundaries];
    [self.request setHTTPBodyStream:self.bodyStream];
    
    [self.request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", self.boundary] forHTTPHeaderField:@"Content-Type"];
    [self.request setValue:[NSString stringWithFormat:@"%llu", [self.bodyStream contentLength]] forHTTPHeaderField:@"Cotent-Length"];
    
    return self.request;
}
@end

#pragma mark - 

@interface NSStream ()
@property (readwrite) NSStreamStatus streamStatus;
@property (readwrite, copy) NSError *streamError;
@end


@interface ZCMultipartBodyStream () <NSCopying>
@property (readwrite, nonatomic, assign) NSStringEncoding stringEncoding;
@property (readwrite, nonatomic, strong) NSMutableArray *HTTPBodyParts;
@property (readwrite, nonatomic, strong) NSEnumerator *HTTPBodyPartEnumerator;
@property (readwrite, nonatomic, strong) ZCHTTPBodyPart *currentHTTPBodyPart;
@property (readwrite, nonatomic, strong) NSOutputStream *outputStream;
@property (readwrite, nonatomic, strong) NSMutableData *buffer;
@end

@implementation ZCMultipartBodyStream
#if (defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000) || (defined(__MAC_OS_X_VERSION_MAX_ALLOWED) && __MAC_OS_X_VERSION_MAX_ALLOWED >= 1100)
@synthesize delegate;
#endif
@synthesize streamStatus;
@synthesize streamError;

- (instancetype)initWithStringEncoding:(NSStringEncoding)encoding{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.stringEncoding = encoding;
    self.HTTPBodyParts = [NSMutableArray array];
    self.numberOfBytesInPacket = NSIntegerMax;
    
    return self;
}

- (void)setInitialAndFinalBoundaries{
    if ([self.HTTPBodyParts count] > 0) {
        for (ZCHTTPBodyPart *bodyPart in self.HTTPBodyParts) {
            bodyPart.hasInitialBoundary = NO;
            bodyPart.hasFinalBoundary = NO;
        }
        
        [[self.HTTPBodyParts firstObject] setHasInitialBoundary:YES];
        [[self.HTTPBodyParts lastObject] setHasFinalBoundary:YES];
    }
}

- (void)appendHTTPBodyPart:(ZCHTTPBodyPart *)bodyPart{
    [self.HTTPBodyParts addObject:bodyPart];
}

- (BOOL)isEmpty{
    return [self.HTTPBodyParts count] == 0;
}

#pragma mark - NSInputStream

- (NSInteger)read:(uint8_t *)buffer
        maxLength:(NSUInteger)len{
    if ([self streamStatus] == NSStreamStatusClosed) {
        return 0;
    }
    
    NSInteger totalNumberOfBytesRead = 0;
    
    while ((NSUInteger)totalNumberOfBytesRead < MIN(len, self.numberOfBytesInPacket)) {
        if (!self.currentHTTPBodyPart || ![self.HTTPBodyPartEnumerator nextObject]) {
            break;
        } else {
            NSUInteger maxLength = MIN(len, self.numberOfBytesInPacket) - (NSUInteger)totalNumberOfBytesRead;
            NSInteger numberOfBytesRead = [self.currentHTTPBodyPart read:&buffer[totalNumberOfBytesRead] maxLength:maxLength];
            
            if (numberOfBytesRead == -1) {
                self.streamError = self.currentHTTPBodyPart.inputStream.streamError;
                break;
            } else {
                totalNumberOfBytesRead += numberOfBytesRead;
                
                if (self.delay > 0.0f) {
                    [NSThread sleepForTimeInterval:self.delay];
                }
            }
        }
    }
    
    return totalNumberOfBytesRead;
}

- (BOOL)getBuffer:(uint8_t * _Nullable *)buffer
           length:(NSUInteger *)len{
    return NO;
}

- (BOOL)hasBytesAvailable{
    return [self streamStatus] == NSStreamStatusOpen;
}

#pragma mark - NSStream

- (void)open{
    if (self.streamStatus == NSStreamStatusOpen) {
        return;
    }
    
    self.streamStatus = NSStreamStatusOpen;
    
    [self setInitialAndFinalBoundaries];
    self.HTTPBodyPartEnumerator = [self.HTTPBodyParts objectEnumerator];
}

- (void)close{
    self.streamStatus = NSStreamStatusClosed;
}

- (id)propertyForKey:(NSStreamPropertyKey)key{
    return nil;
}

- (BOOL)setProperty:(id)property forKey:(NSStreamPropertyKey)key{
    return NO;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode{
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode{
}

- (unsigned long long)contentLength{
    unsigned long long legth = 0;
    for (ZCHTTPBodyPart *bodyPart in self.HTTPBodyParts) {
        legth += [bodyPart contentLength];
    }
    return legth;
}

#pragma mark - Undocumented CFReadStream Bridged Methods

- (void)_scheduleInCFRunLoop:(__unused CFRunLoopRef)aRunLoop forMode:(__unused CFStringRef)aMode{
}

- (void)_unscheduleFromCFRunLoop:(__unused CFRunLoopRef)aRunLoop forMode:(__unused CFStringRef)aMode{
}

- (BOOL)_setCFClientFlags:(__unused CFOptionFlags)inFlags callback:(__unused CFReadStreamClientCallBack)inCallback context:(__unused CFStreamClientContext *)inContext{
    return NO;
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone{
    ZCMultipartBodyStream *bodyStreamCopy = [[[self class] allocWithZone:zone] initWithStringEncoding:self.stringEncoding];
    
    for (ZCHTTPBodyPart *bodyPart in self.HTTPBodyParts) {
        [bodyStreamCopy appendHTTPBodyPart:[bodyPart copy]];
    }

    [bodyStreamCopy setInitialAndFinalBoundaries];
    
    return bodyStreamCopy;
}

@end

#pragma mark - 

typedef enum {
    ZCEnccapsulationBoundaryPhase = 1,
    ZCHeaderPhase                 = 2,
    ZCBodyPhase                   = 3,
    ZCFinalBoundaryPhase          = 4,
} ZCHTTPBodyPartReadPhase;

@interface ZCHTTPBodyPart () <NSCopying>{
    ZCHTTPBodyPartReadPhase _phase;
    NSInputStream *_inputStream;
    unsigned long long _phaseReadOffset;
}

- (BOOL)transitionToNextPhase;
- (NSInteger)readData:(NSData *)data
           intoBuffer:(uint8_t *)buffer
            maxLength:(NSUInteger)lenght;
@end

@implementation ZCHTTPBodyPart

- (instancetype)init{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    [self transitionToNextPhase];
    
    return self;
}

- (void)dealloc{
    if (_inputStream) {
        [_inputStream close];
        _inputStream = nil;
    }
}

- (NSInputStream *)inputStream{
    if (!_inputStream) {
        if ([self.body isKindOfClass:[NSData class]]) {
            _inputStream = [NSInputStream inputStreamWithData:self.body];
        } else if ([self.body isKindOfClass:[NSURL class]]){
            _inputStream = [NSInputStream inputStreamWithURL:self.body];
        } else if ([self.body isKindOfClass:[NSInputStream class]]){
            _inputStream = self.body;
        } else {
            _inputStream = [NSInputStream inputStreamWithData:[NSData data]];
        }
    }
    
    return _inputStream;
}

- (NSString *)stringForHeaders{
    NSMutableString *headerString = [NSMutableString string];
    for (NSString *field in [self.headers allKeys]) {
        [headerString appendString:[NSString stringWithFormat:@"%@: %@%@", field, [self.headers valueForKey:field], kZCMultipartFormCRLF]];
    }
    [headerString appendString:kZCMultipartFormCRLF];
    
    return [NSString stringWithString:headerString];
}

- (unsigned long long)contentLength{
    unsigned long long length = 0;
    
    NSData *encapsulationBoundaryData = [([self hasInitialBoundary] ? ZCMultipartFormInitialBoundary(self.boundary) : ZCMultipartFormEncapsulationBoundary(self.boundary)) dataUsingEncoding:self.stringEncoding];
    length += [encapsulationBoundaryData length];
    
    NSData *headersData = [[self stringForHeaders] dataUsingEncoding:self.stringEncoding];
    length += [headersData length];
    
    length += _bodyContentLength;
    
    NSData *closingBoundaryData = ([self hasFinalBoundary] ? [ZCMultipartFormFinalBoundary(self.boundary) dataUsingEncoding:self.stringEncoding] : [NSData data]);
    length += [closingBoundaryData length];
    
    return length;
}

- (BOOL)hasBytesAvailable{
    if (_phase == ZCFinalBoundaryPhase) {
        return YES;
    }
    
    switch (self.inputStream.streamStatus) {
        case NSStreamStatusNotOpen:
        case NSStreamStatusOpening:
        case NSStreamStatusOpen:
        case NSStreamStatusReading:
        case NSStreamStatusWriting:
            return YES;
        case NSStreamStatusAtEnd:
        case NSStreamStatusClosed:
        case NSStreamStatusError:
        default:
            return NO;
    }
}

- (NSInteger)read:(uint8_t *)buffer
        maxLength:(NSUInteger)length{
    NSInteger totalNumberOfBytesRead = 0;
    
    if (_phase == ZCEnccapsulationBoundaryPhase) {
        NSData *encapsulationBoundaryData = [([self hasInitialBoundary] ? ZCMultipartFormInitialBoundary(self.boundary) : ZCMultipartFormEncapsulationBoundary(self.boundary)) dataUsingEncoding:self.stringEncoding];
        totalNumberOfBytesRead += [self readData:encapsulationBoundaryData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }
    
    if (_phase == ZCHeaderPhase) {
        NSData *headersData = [[self stringForHeaders] dataUsingEncoding:self.stringEncoding];
        totalNumberOfBytesRead += [self readData:headersData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }
    
    if (_phase == ZCBodyPhase) {
        NSInteger numberOfBytesRead = 0;
        
        numberOfBytesRead += [self.inputStream read:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
        if (numberOfBytesRead == -1) {
            return -1;
        } else {
            totalNumberOfBytesRead += numberOfBytesRead;
            
            if ([self.inputStream streamStatus] >= NSStreamStatusAtEnd) {
                [self transitionToNextPhase];
            }
        }
    }
    
    if (_phase == ZCFinalBoundaryPhase) {
        NSData *colosingBoundaryData = ([self hasFinalBoundary] ? [ZCMultipartFormFinalBoundary(self.boundary) dataUsingEncoding:self.stringEncoding] : [NSData data]);
        totalNumberOfBytesRead += [self readData:colosingBoundaryData intoBuffer:&buffer[totalNumberOfBytesRead] maxLength:(length - (NSUInteger)totalNumberOfBytesRead)];
    }
    
    return totalNumberOfBytesRead;
}

- (NSInteger)readData:(NSData *)data
           intoBuffer:(uint8_t *)buffer
            maxLength:(NSUInteger)lenght{
    NSRange range = NSMakeRange((NSUInteger)_phaseReadOffset, MIN([data length] - ((NSUInteger)_phaseReadOffset), lenght));
    [data getBytes:buffer range:range];
    
    _phaseReadOffset += range.length;
    
    if (((NSUInteger)_phaseReadOffset) >= [data length]) {
        [self transitionToNextPhase];
    }
    
    return (NSInteger)range.length;
}
        
- (BOOL)transitionToNextPhase{
    if (![[NSThread currentThread] isMainThread]) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self transitionToNextPhase];
        });
        return YES;
    }
    
    switch (_phase) {
        case ZCEnccapsulationBoundaryPhase:
            _phase = ZCHeaderPhase;
            break;
        case ZCHeaderPhase:
            [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
            [self.inputStream open];
            _phase = ZCBodyPhase;
            break;
        case ZCBodyPhase:
            [self.inputStream close];
            _phase = ZCFinalBoundaryPhase;
            break;
        case ZCFinalBoundaryPhase:
        default:
            _phase = ZCEnccapsulationBoundaryPhase;
            break;
    }
    
    _phaseReadOffset = 0;
    
    return YES;
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone{
    ZCHTTPBodyPart *bodyPart = [[[self class] allocWithZone:zone] init];
    
    bodyPart.stringEncoding = self.stringEncoding;
    bodyPart.headers = self.headers;
    bodyPart.bodyContentLength = self.bodyContentLength;
    bodyPart.body = self.body;
    bodyPart.boundary = self.boundary;
    
    return bodyPart;
}

@end

#pragma mark - 

@implementation ZCJSONRequestSerializer

+ (instancetype)serializer{
    return [self serializerWithWritingOptions:(NSJSONWritingOptions)0];
}

+ (instancetype)serializerWithWritingOptions:(NSJSONWritingOptions)writingOptions{
    ZCJSONRequestSerializer *serializer = [[self alloc] init];
    serializer.writingOptions = writingOptions;
    
    return serializer;
}

#pragma mark - ZCURLRequestSerialization

- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing  _Nullable *)error{
    NSParameterAssert(request);
    
    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[[request HTTPMethod] uppercaseString]]) {
        return [super requestBySerializingRequest:request withParameters:parameters error:error];
    }
    
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    
    [self.HTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * _Nonnull stop) {
        if (![request valueForHTTPHeaderField:field]) {
            [mutableRequest setValue:value forHTTPHeaderField:field];
        }
    }];
    
    if (parameters) {
        if (![mutableRequest valueForHTTPHeaderField:@"Content-Type"]) {
            [mutableRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        }
        
        if (![NSJSONSerialization isValidJSONObject:parameters]) {
            if (error) {
                NSDictionary *userInfo = @{NSLocalizedFailureReasonErrorKey: NSLocalizedStringFromTable(@"The 'parameters argument is not valid JSON'", @"ZCNetworking", nil)};
                *error = [[NSError alloc] initWithDomain:ZCURLRequestSerializationErrorDomain code:NSURLErrorCannotDecodeContentData userInfo:userInfo];
            }
            return nil;
        }
        
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:parameters options:self.writingOptions error:error];
        
        if (!jsonData) {
            return nil;
        }
        
        [mutableRequest setHTTPBody:jsonData];
    }
    
    return mutableRequest;
}

#pragma mark - NSSecureCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
    self.writingOptions = [[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(writingOptions))] unsignedIntegerValue];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [super encodeWithCoder:aCoder];
    
    [aCoder encodeInteger:self.writingOptions forKey:NSStringFromSelector(@selector(writingOptions))];
}
#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone{
    ZCJSONRequestSerializer *serializer = [super copyWithZone:zone];
    self.writingOptions = self.writingOptions;
    
    return serializer;
}

@end

#pragma mark - 

@implementation ZCPropertyListRequestSerializer

+ (instancetype)serializer{
    return [self serializerWithFormate:NSPropertyListXMLFormat_v1_0 writeOptions:0];
}

+ (instancetype)serializerWithFormate:(NSPropertyListFormat)format writeOptions:(NSPropertyListWriteOptions)writeOptions{
    ZCPropertyListRequestSerializer *serializer = [[self alloc] init];
    serializer.format = format;
    serializer.writeOptions = writeOptions;
    
    return serializer;
}

#pragma mark - ZCURLRequestSerializer

- (NSURLRequest *)requestBySerializingRequest:(NSURLRequest *)request
                               withParameters:(id)parameters
                                        error:(NSError *__autoreleasing  _Nullable *)error{
    NSParameterAssert(request);
    
    if ([self.HTTPMethodsEncodingParametersInURI containsObject:[[request HTTPMethod] uppercaseString]]) {
        return [super requestBySerializingRequest:request withParameters:parameters error:error];
    }
    
    NSMutableURLRequest *mutableRequest = [request mutableCopy];
    
    [self.HTTPRequestHeaders enumerateKeysAndObjectsUsingBlock:^(id field, id value, BOOL * _Nonnull stop) {
        if (![request valueForHTTPHeaderField:field]) {
            [mutableRequest setValue:value forHTTPHeaderField:field];
        }
    }];
    
    if (parameters) {
        if (![mutableRequest valueForHTTPHeaderField:@"Content-Type"]) {
            [mutableRequest setValue:@"application/x-plist" forHTTPHeaderField:@"Content-Type"];
        }
        
        NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:parameters format:self.format options:self.writeOptions error:error];
        
        if (!plistData) {
            return nil;
        }
        
        [mutableRequest setHTTPBody:plistData];
    }
    
    return mutableRequest;
    
}

#pragma mark - NSSecuerCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return nil;
    }
    
    self.format = (NSPropertyListFormat)[[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(format))] unsignedIntegerValue];
    self.writeOptions = [[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(writeOptions))] unsignedIntegerValue];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [super encodeWithCoder:aCoder];
    
    [aCoder encodeInteger:self.format forKey:NSStringFromSelector(@selector(format))];
    [aCoder encodeObject:@(self.writeOptions) forKey:NSStringFromSelector(@selector(writeOptions))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone{
    ZCPropertyListRequestSerializer *serializer = [super copyWithZone:zone];
    serializer.format = self.format;
    serializer.writeOptions = self.writeOptions;
    
    return serializer;
}

@end
