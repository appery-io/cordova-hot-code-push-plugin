//
//  CDVWKWebViewEngine+HCPPlugin_ReadAccessURL.m
//
//  Created by Nikolay Demyankov on 04.04.16.
//

#import "CDVWKWebViewEngine+HCPPlugin_ReadAccessURL.h"
#import <objc/message.h>
#import "HCPFilesStructure.h"

#define CDV_WKWEBVIEW_FILE_URL_LOAD_SELECTOR @"loadFileURL:allowingReadAccessToURL:"

#if defined __has_include && __has_include ("CDVWKWebViewEngine.h")
@implementation CDVWKWebViewEngine (HCPPlugin_ReadAccessURL)
#else
#if CORDOVA_VERSION_MIN_REQUIRED >= __CORDOVA_6_1_0
#import <objc/runtime.h>
@implementation CDVWebViewEngine (HCPPlugin_ReadAccessURL)
+ (void)load {
    SEL selector = NSSelectorFromString(@"createConfigurationFromSettings:");
    Method originalMethod = class_getInstanceMethod([CDVWebViewEngine class], selector);
    IMP originalImp = method_getImplementation(originalMethod);
    typedef WKWebViewConfiguration* (*send_type)(id, SEL , NSDictionary*);
    send_type originalImpSend = (send_type)originalImp;
    
    IMP newImp = imp_implementationWithBlock(^(id _self, NSDictionary* settings){
        // Get the original configuration
        WKWebViewConfiguration* configuration = originalImpSend(_self, selector, settings);

        // allow access to file api
        @try {
            [configuration.preferences setValue:@TRUE forKey:@"allowFileAccessFromFileURLs"];
        }
        @catch (NSException *exception) {}
        
        @try {
            [configuration setValue:@TRUE forKey:@"allowUniversalAccessFromFileURLs"];
        }
        @catch (NSException *exception) {}
        
        return configuration;
    });
    
    method_setImplementation(originalMethod, newImp);
}

#else
#warning CANNOT FIND ANY WebViewEngine Include
#endif
#endif

#if FOUND_WK_WEB_VIEW==1

/**
 * If path is under an HCP release www folder, return that www folder path.
 * Example: .../cordova-hot-code-push-plugin/2026.08.05-xx/www/index.html → .../www
 */
static NSString *HCPWwwFolderFromPath(NSString *path) {
    if (path.length == 0) {
        return nil;
    }
    NSRange marker = [path rangeOfString:@"/cordova-hot-code-push-plugin/"];
    if (marker.location == NSNotFound) {
        return nil;
    }
    NSRange wwwRange = [path rangeOfString:@"/www/" options:0 range:NSMakeRange(marker.location, path.length - marker.location)];
    if (wwwRange.location == NSNotFound) {
        // exact .../www or .../www/
        if ([path hasSuffix:@"/www"] || [path hasSuffix:@"/www/"]) {
            return [path hasSuffix:@"/"] ? [path substringToIndex:path.length - 1] : path;
        }
        return nil;
    }
    return [path substringToIndex:wwwRange.location + 4]; // include "/www"
}

- (void)hcp_setIonicAssetPath:(NSString *)wwwPath {
    if (wwwPath.length == 0) {
        return;
    }
    @try {
        [self setValue:wwwPath forKey:@"basePath"];
    } @catch (NSException *e) {}

    NSObject *handler = nil;
    @try {
        handler = [self valueForKey:@"handler"];
    } @catch (NSException *e) {}
    if (!handler) {
        NSString *scheme = @"ionic";
        @try {
            NSString *local = [self performSelector:@selector(CDV_LOCAL_SERVER)];
            if ([local containsString:@"://"]) {
                scheme = [local componentsSeparatedByString:@"://"].firstObject;
            }
        } @catch (NSException *e) {}
        handler = [[((WKWebView*)self.engineWebView) configuration] urlSchemeHandlerForURLScheme:scheme];
        if (!handler) {
            handler = [[((WKWebView*)self.engineWebView) configuration] urlSchemeHandlerForURLScheme:@"ionic"];
        }
        if (!handler) {
            handler = [[((WKWebView*)self.engineWebView) configuration] urlSchemeHandlerForURLScheme:@"app"];
        }
    }
    if (handler && [handler respondsToSelector:@selector(setAssetPath:)]) {
        [handler performSelector:@selector(setAssetPath:) withObject:wwwPath];
    }
}

- (id)loadRequest:(NSURLRequest*)request
{
    if ([self canLoadRequest:request]) { // can load, differentiate between file urls and other schemes
        if (request.URL.fileURL) {
            NSString *filePath = request.URL.path;
            NSString *hcpWww = HCPWwwFolderFromPath(filePath);

            NSString *scheme = @"ionic";
            NSString *localServer = nil;
            @try {
                localServer = [self performSelector:@selector(CDV_LOCAL_SERVER)];
                if ([localServer containsString:@"://"]) {
                    scheme = [localServer componentsSeparatedByString:@"://"].firstObject;
                }
            } @catch (NSException *e) {}

            NSObject *handler = [[((WKWebView*)self.engineWebView) configuration] urlSchemeHandlerForURLScheme:scheme];
            if (!handler) {
                handler = [[((WKWebView*)self.engineWebView) configuration] urlSchemeHandlerForURLScheme:@"ionic"];
            }
            if (!handler) {
                handler = [[((WKWebView*)self.engineWebView) configuration] urlSchemeHandlerForURLScheme:@"app"];
            }

            if (handler) {
                NSURL *localServerUrl = localServer.length
                    ? [NSURL URLWithString:localServer]
                    : [NSURL URLWithString:[NSString stringWithFormat:@"%@://localhost", scheme]];

                if (hcpWww.length > 0) {
                    // Serve HCP content from the release www folder as ionic/app://localhost/
                    // so relative scripts and ionic://localhost/cordova.js resolve correctly.
                    [self hcp_setIonicAssetPath:hcpWww];
                    NSURL *url = localServerUrl;
                    if (![filePath isEqualToString:hcpWww] &&
                        ![filePath isEqualToString:[hcpWww stringByAppendingString:@"/"]] &&
                        ![filePath hasSuffix:@"/index.html"]) {
                        NSString *relative = [filePath substringFromIndex:hcpWww.length];
                        if ([relative hasPrefix:@"/"]) {
                            relative = [relative substringFromIndex:1];
                        }
                        if (relative.length > 0) {
                            url = [localServerUrl URLByAppendingPathComponent:relative];
                        }
                    }
                    if (request.URL.query) {
                        url = [NSURL URLWithString:[@"?" stringByAppendingString:request.URL.query] relativeToURL:url];
                    }
                    if (request.URL.fragment) {
                        url = [NSURL URLWithString:[@"#" stringByAppendingString:request.URL.fragment] relativeToURL:url];
                    }
                    request = [NSURLRequest requestWithURL:url];
                    return [(WKWebView*)self.engineWebView loadRequest:request];
                }

                // Non-HCP file URL (bundle) — keep Ionic default behaviour
                NSURL* startURL = [NSURL URLWithString:((CDVViewController *)self.viewController).startPage];
                NSString* startFilePath = [self.commandDelegate pathForResource:[startURL path]];
                NSURL *url = [localServerUrl URLByAppendingPathComponent:request.URL.path];
                if ([request.URL.path isEqualToString:startFilePath]) {
                    url = localServerUrl;
                }
                if(request.URL.query) {
                    url = [NSURL URLWithString:[@"?" stringByAppendingString:request.URL.query] relativeToURL:url];
                }
                if(request.URL.fragment) {
                    url = [NSURL URLWithString:[@"#" stringByAppendingString:request.URL.fragment] relativeToURL:url];
                }
                request = [NSURLRequest requestWithURL:url];
                return [(WKWebView*)self.engineWebView loadRequest:request];
            } else {
                SEL wk_sel = NSSelectorFromString(CDV_WKWEBVIEW_FILE_URL_LOAD_SELECTOR);
                
                // by default we set allowingReadAccessToURL property to the plugin's root folder,
                // so the WKWebView would load our updates from it.
                NSURL* readAccessUrl = [HCPFilesStructure pluginRootFolder];
                
                // if we are loading index page from the bundle - we need to go up in the folder structure, so the next load from the external storage would work
                if (![request.URL.absoluteString containsString:readAccessUrl.absoluteString]) {
                    readAccessUrl = [[[request.URL URLByDeletingLastPathComponent] URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
                }
                
                return ((id (*)(id, SEL, id, id))objc_msgSend)(self.engineWebView, wk_sel, request.URL, readAccessUrl);
            }
        } else {
            return [(WKWebView*)self.engineWebView loadRequest:request];
        }
    } else { // can't load, print out error
        NSString* errorHtml = [NSString stringWithFormat:
                               @"<!doctype html>"
                               @"<title>Error</title>"
                               @"<div style='font-size:2em'>"
                               @"   <p>The WebView engine '%@' is unable to load the request: %@</p>"
                               @"   <p>Most likely the cause of the error is that the loading of file urls is not supported in iOS %@.</p>"
                               @"</div>",
                               NSStringFromClass([self class]),
                               [request.URL description],
                               [[UIDevice currentDevice] systemVersion]
                               ];
        return [self loadHTMLString:errorHtml baseURL:nil];
    }
}

@end

#endif
