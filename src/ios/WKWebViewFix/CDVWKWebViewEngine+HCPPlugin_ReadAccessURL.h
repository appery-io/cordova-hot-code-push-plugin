//
//  CDVWKWebViewEngine+HCPPlugin_ReadAccessURL.h
//
//  Created by Nikolay Demyankov on 04.04.16.
//

#import <Cordova/CDVAvailability.h>

#if defined __has_include && __has_include ("CDVWKWebViewEngine.h")
    #import "CDVWKWebViewEngine.h"
    #define FOUND_WK_WEB_VIEW 1
    @interface CDVWKWebViewEngine (HCPPlugin_ReadAccessURL)
    @end
#else
    #if CORDOVA_VERSION_MIN_REQUIRED >= __CORDOVA_6_1_0
        #define FOUND_WK_WEB_VIEW 1
        #import "../../../../CordovaLib/Classes/Private/Plugins/CDVWebViewEngine/CDVWebViewEngine.h"
        @interface CDVWebViewEngine (HCPPlugin_ReadAccessURL)
        @end
    #else
        #warning CANNOT FIND ANY WebViewEngine Include
    #endif
#endif
