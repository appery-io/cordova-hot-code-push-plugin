//
//  HCPContentManifest.m
//
//  Created by Nikolay Demyankov on 10.08.15.
//

#import "HCPContentManifest.h"
#import "HCPManifestFile.h"

@interface HCPContentManifest()

@property (nonatomic, readwrite, strong) NSArray *files;

@end

@implementation HCPContentManifest

#pragma mark Public API

+ (BOOL)isNativeBridgeFile:(NSString *)fileName {
    if (fileName.length == 0) {
        return NO;
    }
    NSString *name = [fileName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    if ([name hasPrefix:@"./"]) {
        name = [name substringFromIndex:2];
    }
    // Keep native cordova bridge + plugin JS from the installed binary.
    // Do NOT block cordova.<hash>.js — updated index.html references those files.
    if ([name isEqualToString:@"cordova.js"] || [name isEqualToString:@"cordova_plugins.js"] ||
        [name isEqualToString:@"cordova.js.map"] || [name isEqualToString:@"cordova_plugins.js.map"]) {
        return YES;
    }
    if ([name hasPrefix:@"plugins/"]) {
        return YES;
    }
    return NO;
}

- (HCPContentManifest *)manifestWithoutNativeBridgeFiles {
    NSMutableArray *filtered = [[NSMutableArray alloc] init];
    for (HCPManifestFile *file in self.files) {
        if (![HCPContentManifest isNativeBridgeFile:file.name]) {
            [filtered addObject:file];
        }
    }
    HCPContentManifest *manifest = [[HCPContentManifest alloc] init];
    manifest.files = filtered;
    return manifest;
}

- (HCPManifestDiff *)calculateDifference:(HCPContentManifest *)comparedManifest {
    NSMutableArray *addedFiles = [[NSMutableArray alloc] init];
    NSMutableArray *changedFiles = [[NSMutableArray alloc] init];
    NSMutableArray *deletedFiles = [[NSMutableArray alloc] init];

    // find deleted and updated files
    for (HCPManifestFile *oldFile in self.files) {
        if ([HCPContentManifest isNativeBridgeFile:oldFile.name]) {
            // Keep native bridge from the installed app (Appery manifests overwrite cordova_plugins.js)
            continue;
        }
        BOOL isDeleted = YES;
        for (HCPManifestFile *newFile in comparedManifest.files) {
            if ([oldFile.name isEqualToString:newFile.name]) {
                isDeleted = NO;
                if (![newFile.md5Hash isEqualToString:oldFile.md5Hash] && ![HCPContentManifest isNativeBridgeFile:newFile.name]) {
                    [changedFiles addObject:newFile];
                }
            }
        }
        if (isDeleted) {
            [deletedFiles addObject:oldFile];
        }
    }
    
    // find new files
    for (HCPManifestFile *newFile in comparedManifest.files) {
        if ([HCPContentManifest isNativeBridgeFile:newFile.name]) {
            continue;
        }
        BOOL isFound = NO;
        for (HCPManifestFile *oldFile in self.files) {
            if ([newFile.name isEqualToString:oldFile.name]) {
                isFound = YES;
                break;
            }
        }
        if (!isFound) {
            [addedFiles addObject:newFile];
        }
    }

    
    return [[HCPManifestDiff alloc] initWithAddedFiles:addedFiles changedFiles:changedFiles deletedFiles:deletedFiles];
}

#pragma mark HCPJsonConvertable implmenetation

- (id)toJson {
    NSMutableArray *jsonObject = [[NSMutableArray alloc] init];
    for (HCPManifestFile *manifestFile in self.files) {
        id manifestFileObj = [manifestFile toJson];
        if (manifestFileObj) {
            [jsonObject addObject:manifestFileObj];
        }
    }
    
    return jsonObject;
}

+ (instancetype)instanceFromJsonObject:(id)json {
    if (![json isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    NSArray *jsonObject = json;
    NSMutableArray *manifestFilesList = [[NSMutableArray alloc] initWithCapacity:jsonObject.count];
    for (NSDictionary *manifestFileObject in jsonObject) {
        HCPManifestFile* manifestFile = [HCPManifestFile instanceFromJsonObject:manifestFileObject];
        if (manifestFile) {
            [manifestFilesList addObject:manifestFile];
        }
    }
    
    HCPContentManifest *manifest = [[HCPContentManifest alloc] init];
    manifest.files = manifestFilesList;
    
    return manifest;
}

@end
