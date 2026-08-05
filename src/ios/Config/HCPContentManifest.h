//
//  HCPContentManifest.h
//
//  Created by Nikolay Demyankov on 10.08.15.
//

#import <Foundation/Foundation.h>

#import "HCPJsonConvertable.h"
#import "HCPManifestDiff.h"

/**
 *  Model for content manifest.
 *  Content manifest is a configuration file, that holds the list of all web project files with they hashes.
 *  Used to determine which files has been removed from the project, which are added or updated.
 */
@interface HCPContentManifest : NSObject<HCPJsonConvertable>

/**
 *  List of web project files.
 *  Objects in the array are the instances of the HCPManifestFile class.
 *
 *  @see HCPManifestFile
 */
@property (nonatomic, readonly, strong) NSArray *files;

/**
 * Files that must remain from the native install (cordova.js, cordova_plugins.js, plugins/*).
 * Hashed cordova.&lt;hash&gt;.js files are NOT included — they must be downloaded with updates.
 */
+ (BOOL)isNativeBridgeFile:(NSString *)fileName;

/**
 * Copy of this manifest without native-bridge files (for persisting installed state).
 */
- (HCPContentManifest *)manifestWithoutNativeBridgeFiles;

/**
 * Find differences between this manifest and the new one.
 * Current object is considered as an old manifest.
 *
 *  @param comparedManifest new manifest, relative to which we will calculate the difference
 *
 *  @return calculated difference between manifests
 *  @see HCPManifestFile
 *  @see HCPManifestDiff
 */
- (HCPManifestDiff *)calculateDifference:(HCPContentManifest *)comparedManifest;

@end
