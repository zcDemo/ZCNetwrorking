//
//  ZCSercurityPolicy.h
//  ZCNetWorking
//
//  Created by dongzhicheng on 2017/7/6.
//  Copyright © 2017年 dongzhicheng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>

typedef NS_ENUM(NSUInteger, ZCSSLPinningMode) {
    ZCSSLPinningModeNone,
    ZCSSLPinningModePublicKey,
    ZCSSLPinningModeCertificate,
};

NS_ASSUME_NONNULL_BEGIN

@interface ZCSercurityPolicy : NSObject <NSSecureCoding, NSCopying>

@property (readonly, nonatomic, assign) ZCSSLPinningMode SSLPinningMode;

@property (nonatomic, strong, nullable) NSSet <NSData *> *pinnedCertificates;

@property (nonatomic, assign) BOOL allowInvalidCetificates;

@property (nonatomic, assign) BOOL validatesDomainName;

+ (NSSet <NSData *> *)certificationsInBundle:(NSBundle *)bundle;

+ (instancetype)defaultPolicy;

+ (instancetype)policyWithPinningMode:(ZCSSLPinningMode)pinningModel;

+ (instancetype)policyWithPinningMode:(ZCSSLPinningMode)pinningModel withPinnedCertificates:(NSSet <NSData *> *)pinnedCertificates;

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(nullable NSString *)domain;

@end

NS_ASSUME_NONNULL_END
