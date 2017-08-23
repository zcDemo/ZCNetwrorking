//
//  ZCSercurityPolicy.m
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import "ZCSercurityPolicy.h"

#import <AssertMacros.h>
#import <Security/SecImportExport.h>

static BOOL ZCSecKeyIsEqualToKey(SecKeyRef key1, SecKeyRef key2){
    return [(__bridge id)key1 isEqual:(__bridge id)key2];
}

static id ZCPublicKeyForCertificate(NSData *certificate){
    id allowedPublicKey = nil;
    SecCertificateRef allowedCertificate;
    SecPolicyRef policy = nil;
    SecTrustRef allowedTrust = nil;
    SecTrustResultType result;
    
    allowedCertificate = SecCertificateCreateWithData(NULL, (__bridge_retained CFDataRef)certificate);
    __Require_noErr_Quiet(allowedCertificate != NULL, _out);
    
    
    policy = SecPolicyCreateBasicX509();
    __Require_noErr_Quiet(SecTrustCreateWithCertificates(allowedCertificate, policy, &allowedTrust), _out);
    __Require_noErr_Quiet(SecTrustEvaluate(allowedTrust, &result), _out);
    
    allowedPublicKey = (__bridge_transfer id)SecTrustCopyPublicKey(allowedTrust);
    
_out:
    if (allowedTrust) {
        CFRelease(allowedTrust);
    }
    
    if (policy) {
        CFRelease(policy);
    }
    
    if (allowedCertificate) {
        CFRelease(allowedCertificate);
    }
    
    return allowedPublicKey;
}

static BOOL ZCServierTrustIsValid(SecTrustRef serverTrust){
    BOOL isValid = NO;
    SecTrustResultType result;
    __Require_noErr_Quiet(SecTrustEvaluate(serverTrust, &result), _out);
    isValid = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
_out:
    return isValid;
}

static NSArray * ZCCertificateTrustChainForServerTrust(SecTrustRef serverTrust){
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        [trustChain addObject:(
         __bridge_transfer NSData *)SecCertificateCopyData(certificate)];
    }
    
    return [NSArray arrayWithArray:trustChain];
}

static NSArray *ZCPublicKeyTrustChainForServerTrust(SecTrustRef serverTrust){
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    CFIndex certificateCount = SecTrustGetCertificateCount(serverTrust);
    NSMutableArray *trustChain = [NSMutableArray arrayWithCapacity:(NSUInteger)certificateCount];
    for (CFIndex i = 0; i < certificateCount; i++) {
        SecCertificateRef certificate = SecTrustGetCertificateAtIndex(serverTrust, i);
        
        SecCertificateRef someCertificates[] = {certificate};
        CFArrayRef certificates = CFArrayCreate(NULL, (const void **)someCertificates, 1, NULL);
        
        SecTrustRef trust;
        __Require_noErr_Quiet(SecTrustCreateWithCertificates(certificates, policy, &trust), _out);
        
        [trustChain addObject:(__bridge_transfer id)SecTrustCopyPublicKey(trust)];
    _out:
        if (trust) {
            CFRelease(trust);
        }
        
        if (certificates) {
            CFRelease(certificates);
        }
        
        continue;
    }
    CFRelease(policy);
    
    return [NSArray arrayWithArray:trustChain];
}

#pragma mark - 

@interface ZCSercurityPolicy ()
@property (readwrite, nonatomic, assign)ZCSSLPinningMode SSLPinningMode;
@property (readwrite, nonatomic, strong) NSSet *pinnedPublicKeys;
@end

@implementation ZCSercurityPolicy

+ (NSSet<NSData *> *)certificationsInBundle:(NSBundle *)bundle{
    NSArray *paths = [bundle pathsForResourcesOfType:@"cer" inDirectory:@"."];
    
    NSMutableSet *certificates = [NSMutableSet setWithCapacity:[paths count]];
    for (NSString *path in paths) {
        NSData *certificateData = [NSData dataWithContentsOfFile:path];
        [certificates addObject:certificateData];
    }
    
    return [NSSet setWithSet:certificates];
}

+ (NSSet *)defaultPinnedCertificates{
    static NSSet *_defaultPinnedCertificates = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        _defaultPinnedCertificates = [self certificationsInBundle:bundle];
    });
    
    return _defaultPinnedCertificates;
}

+ (instancetype)defaultPolicy{
    ZCSercurityPolicy *securityPolicy = [[self alloc] init];
    securityPolicy.SSLPinningMode = ZCSSLPinningModeNone;
    
    return securityPolicy;
}

+ (instancetype)policyWithPinningMode:(ZCSSLPinningMode)pinningModel{
    return [self policyWithPinningMode:pinningModel withPinnedCertificates:[self defaultPinnedCertificates]];
}

+ (instancetype)policyWithPinningMode:(ZCSSLPinningMode)pinningModel withPinnedCertificates:(NSSet<NSData *> *)pinnedCertificates{
    ZCSercurityPolicy *securitPolicy = [[self alloc] init];
    securitPolicy.SSLPinningMode = pinningModel;
    
    [securitPolicy setPinnedCertificates:pinnedCertificates];
    
    return securitPolicy;
}

- (instancetype)init{
    self = [super init];
    if (!self) {
        return nil;
    }

    self.validatesDomainName = YES;
    
    return self;
}

- (void)setPinnedCertificates:(NSSet<NSData *> *)pinnedCertificates{
    _pinnedCertificates = pinnedCertificates;
    
    if (self.pinnedCertificates) {
        NSMutableSet *mutablePinnedPublicKeys = [NSMutableSet setWithCapacity:[self.pinnedCertificates count]];
        for (NSData *certificate in self.pinnedCertificates) {
            id publicKey = ZCPublicKeyForCertificate(certificate);
            if (!publicKey) {
                continue;
            }
            
            [mutablePinnedPublicKeys addObject:publicKey];
        }
        self.pinnedPublicKeys = [NSSet setWithSet:mutablePinnedPublicKeys];
    } else {
        self.pinnedPublicKeys = nil;
    }
}

#pragma mark -

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain{
    if (domain && self.allowInvalidCetificates && self.validatesDomainName && (self.SSLPinningMode == ZCSSLPinningModeNone || [self.pinnedCertificates count] == 0)) {
        return NO;
    }
    
    NSMutableArray *policies = [NSMutableArray array];
    if (self.validatesDomainName) {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }
    
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
    
    if (self.SSLPinningMode == ZCSSLPinningModeNone) {
        return self.allowInvalidCetificates || ZCServierTrustIsValid(serverTrust);
    } else if (!ZCServierTrustIsValid(serverTrust) && !self.allowInvalidCetificates){
        return NO;
    }
    
    switch (self.SSLPinningMode) {
        case ZCSSLPinningModeNone:
        default:
            return NO;
        
        case ZCSSLPinningModeCertificate:{
            NSMutableArray *pinnedCertificates = [NSMutableArray array];
            for (NSData *certificateData in self.pinnedCertificates) {
                [pinnedCertificates addObject:(__bridge_transfer id)SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateData)];
            }
            
            SecTrustSetAnchorCertificates(serverTrust, (__bridge CFArrayRef)pinnedCertificates);
            
            if (!ZCServierTrustIsValid(serverTrust)) {
                return NO;
            }
            
            NSArray *serverCertificates = ZCCertificateTrustChainForServerTrust(serverTrust);
            
            for (NSData *trustChainCertificate in [serverCertificates reverseObjectEnumerator]) {
                if ([self.pinnedCertificates containsObject:trustChainCertificate]) {
                    return YES;
                }
            }
             return NO;
        }
        case ZCSSLPinningModePublicKey:{
            NSUInteger trustedPublicKeyCount = 0;
            NSArray *publicKeys = ZCPublicKeyTrustChainForServerTrust(serverTrust);
            
            for (id trustChainPublicKey in publicKeys) {
                for (id pinnedPublicKey in self.pinnedPublicKeys ) {
                    if (ZCSecKeyIsEqualToKey((__bridge SecKeyRef)trustChainPublicKey, (__bridge SecKeyRef)pinnedPublicKey)) {
                        trustedPublicKeyCount += 1;
                    }
                }
            }
            return trustedPublicKeyCount > 0;
        }
    }
    
    return NO;
}

#pragma mark - NSKeyValueObserving

+ (NSSet<NSString *> *)keyPathsForValuesAffectingPinnedPublicKeys{
    return [NSSet setWithObject:@"pinnedCertificates"];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder{
    self = [self init];
    if (!self) {
        return nil;
    }
    
    self.SSLPinningMode = [[aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(SSLPinningMode))] unsignedIntegerValue];
    self.allowInvalidCetificates = [aDecoder decodeBoolForKey:NSStringFromSelector(@selector(allowInvalidCetificates))];
    self.validatesDomainName = [aDecoder decodeBoolForKey:NSStringFromSelector(@selector(validatesDomainName))];
    self.pinnedCertificates = [aDecoder decodeObjectOfClass:[NSArray class] forKey: NSStringFromSelector(@selector(pinnedCertificates))];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:[NSNumber numberWithUnsignedInteger:self.SSLPinningMode] forKey:NSStringFromSelector(@selector(SSLPinningMode))];
    [aCoder encodeBool:self.allowInvalidCetificates forKey:NSStringFromSelector(@selector(allowInvalidCetificates))];
    [aCoder encodeBool:self.validatesDomainName forKey:NSStringFromSelector(@selector(validatesDomainName))];
    [aCoder encodeObject:self.pinnedCertificates forKey:NSStringFromSelector(@selector(pinnedCertificates))];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone{
    ZCSercurityPolicy *securityPolicy = [[[self class] allocWithZone:zone] init];
    securityPolicy.SSLPinningMode = self.SSLPinningMode;
    securityPolicy.allowInvalidCetificates = self.allowInvalidCetificates;
    securityPolicy.validatesDomainName = self.validatesDomainName;
    securityPolicy.pinnedCertificates = [self.pinnedCertificates copyWithZone:zone];
    
    return securityPolicy;
}

@end
