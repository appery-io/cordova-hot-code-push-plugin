//
//  HCPAppUpdateRequestAlertDialog.m
//
//  Created by Nikolay Demyankov on 26.08.15.
//

#import "HCPAppUpdateRequestAlertDialog.h"
#import <UIKit/UIKit.h>

@interface HCPAppUpdateRequestAlertDialog() {
    NSString *_message;
    NSString *_storeUrl;
    void (^_onSuccess)(void);
    void (^_onFailure)(void);
}

@end

@implementation HCPAppUpdateRequestAlertDialog

- (instancetype)initWithMessage:(NSString *)message storeUrl:(NSString *)storeUrl onSuccessBlock:(void (^)(void))onSuccess onFailureBlock:(void (^)(void))onFailure {
    self = [super init];
    if (self) {
        _message = message;
        _storeUrl = storeUrl;
        _onSuccess = onSuccess;
        _onFailure = onFailure;
    }
    
    return self;
}

- (void)show {
    NSString *positiveButtonTitle = NSLocalizedString(@"OK", @"");
    NSString *negativeButtontitle = NSLocalizedString(@"Cancel", @"");

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@""
                                                                   message:_message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:positiveButtonTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        if (_onSuccess) {
            _onSuccess();
        }
        NSURL *url = [NSURL URLWithString:_storeUrl];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
        (void)weakSelf;
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:negativeButtontitle
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
        if (_onFailure) {
            _onFailure();
        }
        (void)weakSelf;
    }]];

    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
        }
        if (window != nil) break;
    }
    UIViewController *root = window.rootViewController;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    [root presentViewController:alert animated:YES completion:nil];
}

@end
