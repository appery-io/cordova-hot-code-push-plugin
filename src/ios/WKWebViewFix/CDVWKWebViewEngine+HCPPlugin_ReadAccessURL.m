//
//  CDVWKWebViewEngine+HCPPlugin_ReadAccessURL.m
//
//  Created by Nikolay Demyankov on 04.04.16.
//
//  Note: We intentionally do NOT override -[CDVWKWebViewEngine loadRequest:] when
//  cordova-plugin-ionic-webview is present. Ionic already maps file URLs to
//  scheme://localhost. HCP retargets IONAssetHandler via setAssetPath: in HCPPlugin
//  before Cordova loadStartPage (see resetIndexPageToExternalStorage).
//

#import "CDVWKWebViewEngine+HCPPlugin_ReadAccessURL.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import "HCPFilesStructure.h"

#if defined __has_include && __has_include ("CDVWKWebViewEngine.h")
@implementation CDVWKWebViewEngine (HCPPlugin_ReadAccessURL)
// Ionic WebView: no loadRequest override — see file header.
@end
#else
#if CORDOVA_VERSION_MIN_REQUIRED >= __CORDOVA_6_1_0
@implementation CDVWebViewEngine (HCPPlugin_ReadAccessURL)
+ (void)load {
    SEL selector = NSSelectorFromString(@"createConfigurationFromSettings:");
    Method originalMethod = class_getInstanceMethod([CDVWebViewEngine class], selector);
    if (!originalMethod) { return; }
    IMP originalImp = method_getImplementation(originalMethod);
    typedef WKWebViewConfiguration* (*send_type)(id, SEL , NSDictionary*);
    send_type originalImpSend = (send_type)originalImp;
    IMP newImp = imp_implementationWithBlock(^(id _self, NSDictionary* settings){
        WKWebViewConfiguration* configuration = originalImpSend(_self, selector, settings);
        @try { [configuration.preferences setValue:@TRUE forKey:@"allowFileAccessFromFileURLs"]; } @catch (NSException *exception) {}
        @try { [configuration setValue:@TRUE forKey:@"allowUniversalAccessFromFileURLs"]; } @catch (NSException *exception) {}
        return configuration;
    });
    method_setImplementation(originalMethod, newImp);
}
@end
#else
#warning CANNOT FIND ANY WebViewEngine Include
#endif
#endif
