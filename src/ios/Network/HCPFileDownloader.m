//
//  HCPFileDownloader.m
//
//  Created by Nikolay Demyankov on 11.08.15.
//

#import "HCPFileDownloader.h"
#import "HCPManifestFile.h"
#import "NSData+HCPMD5.h"
#import "NSError+HCPExtension.h"

@interface HCPFileDownloader()<NSURLSessionDownloadDelegate> {
    NSArray *_filesList;
    NSURL *_contentURL;
    NSURL *_folderURL;
    NSDictionary *_headers;
    
    NSURLSession *_session;
    HCPFileDownloadCompletionBlock _complitionHandler;
    NSUInteger _downloadCounter;
    NSUInteger _retryCount;
}

@end

static NSUInteger const TIMEOUT = 600;
static NSUInteger const MAX_RETRIES = 3;

@implementation HCPFileDownloader

#pragma mark Public API

- (instancetype)initWithFiles:(NSArray *)filesList srcDirURL:(NSURL *)contentURL dstDirURL:(NSURL *)folderURL requestHeaders:(NSDictionary *)headers {
    self = [super init];
    if (self) {
        _filesList = filesList;
        // Ensure content URL is treated as a directory for relative path joins
        NSString *absolute = contentURL.absoluteString;
        if (absolute.length > 0 && ![absolute hasSuffix:@"/"]) {
            contentURL = [NSURL URLWithString:[absolute stringByAppendingString:@"/"]];
        }
        _contentURL = contentURL;
        _folderURL = folderURL;
        _headers = headers;
    }
    
    return self;
}

- (NSURLSession *)sessionWithHeaders:(NSDictionary *)headers {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = TIMEOUT;
    configuration.timeoutIntervalForResource = TIMEOUT;
    configuration.HTTPMaximumConnectionsPerHost = 4;
    if (headers) {
        [configuration setHTTPAdditionalHeaders:headers];
    }
    
    return [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
}

- (void)startDownloadWithCompletionBlock:(HCPFileDownloadCompletionBlock)block {
    _complitionHandler = block;
    _downloadCounter = 0;
    _retryCount = 0;
    _session = [self sessionWithHeaders:_headers];
    
    if (_filesList.count == 0) {
        _complitionHandler(nil);
        return;
    }
    
    [self launchDownloadTaskForFile:_filesList[0]];
}

#pragma mark NSURLSessionTaskDelegate / DownloadDelegate

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    if (error && _complitionHandler) {
        _complitionHandler(error);
        _session = nil;
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // Critical: without this, network failures hang the update forever
    // (didFinishDownloadingToURL is never called on task failure).
    if (error == nil) {
        return;
    }
    
    if ([self shouldRetry]) {
        NSLog(@"CHCP: download error for %@, retry %lu/%lu: %@",
              task.originalRequest.URL.absoluteString,
              (unsigned long)(_retryCount + 1),
              (unsigned long)MAX_RETRIES,
              error.localizedDescription);
        _retryCount++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * _retryCount * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_downloadCounter < _filesList.count) {
                [self launchDownloadTaskForFile:_filesList[_downloadCounter]];
            }
        });
        return;
    }
    
    [_session invalidateAndCancel];
    _session = nil;
    if (_complitionHandler) {
        _complitionHandler(error);
        _complitionHandler = nil;
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)downloadTask.response;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger status = response.statusCode;
        if (status < 200 || status >= 300) {
            NSError *httpError = [NSError errorWithCode:kHCPFailedToDownloadUpdateFilesErrorCode
                                            description:[NSString stringWithFormat:@"HTTP %ld for %@", (long)status, downloadTask.originalRequest.URL.absoluteString]];
            if ([self shouldRetry]) {
                _retryCount++;
                [self launchDownloadTaskForFile:_filesList[_downloadCounter]];
                return;
            }
            [_session invalidateAndCancel];
            _session = nil;
            _complitionHandler(httpError);
            _complitionHandler = nil;
            return;
        }
    }
    
    NSError *error = nil;
    if (![self moveLoadedFile:location forFile:_filesList[_downloadCounter] toFolder:_folderURL error:&error]) {
        if ([self shouldRetry]) {
            _retryCount++;
            [self launchDownloadTaskForFile:_filesList[_downloadCounter]];
            return;
        }
        [_session invalidateAndCancel];
        _session = nil;
        _complitionHandler(error);
        _complitionHandler = nil;
        return;
    }
    
    _retryCount = 0;
    _downloadCounter++;
    if (_downloadCounter >= _filesList.count) {
        [_session finishTasksAndInvalidate];
        _session = nil;
        _complitionHandler(nil);
        _complitionHandler = nil;
        return;
    }
    
    [self launchDownloadTaskForFile:_filesList[_downloadCounter]];
}

- (BOOL)shouldRetry {
    return _retryCount < MAX_RETRIES;
}

- (void)launchDownloadTaskForFile:(HCPManifestFile *)file {
    // Use relative URL construction so nested paths (assets/foo.png) keep their slashes
    NSURL *url = [NSURL URLWithString:file.name relativeToURL:_contentURL].absoluteURL;
    if (url == nil) {
        // Fallback for odd names
        url = [_contentURL URLByAppendingPathComponent:file.name];
    }
    NSLog(@"Starting file download: %@", url.absoluteString);
    
    [[_session downloadTaskWithURL:url] resume];
}

#pragma Private API

/**
 *  Check if loaded file is corrupted.
 */
- (BOOL)isFileCorrupted:(NSURL *)file checksum:(NSString *)checksum {
    NSString *dataHash = [[NSData dataWithContentsOfURL:file] md5];
    if ([dataHash isEqualToString:checksum]) {
        return NO;
    }
    
    NSLog(@"Hash %@ doesn't match the checksum %@", dataHash, checksum);
    
    return YES;
}

/**
 *  Move loaded file from the tmp folder to the download folder.
 */
- (BOOL)moveLoadedFile:(NSURL *)loadedFile forFile:(HCPManifestFile *)file toFolder:(NSURL *)folderURL error:(NSError **)error {
    if ([self isFileCorrupted:loadedFile checksum:file.md5Hash]) {
        NSString *errorMsg = [NSString stringWithFormat:@"File %@ is corrupted", file.name];
        *error = [NSError errorWithCode:kHCPFailedToDownloadUpdateFilesErrorCode description:errorMsg];
        return NO;
    }
    
    // Build destination path segment-by-segment so nested paths work
    NSURL *filePath = folderURL;
    NSArray *parts = [file.name componentsSeparatedByString:@"/"];
    for (NSString *part in parts) {
        if (part.length > 0) {
            filePath = [filePath URLByAppendingPathComponent:part];
        }
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // remove old version of the file
    if ([fileManager fileExistsAtPath:filePath.path]) {
        [fileManager removeItemAtURL:filePath error:nil];
    }
    
    // create storage directories
    [fileManager createDirectoryAtPath:[filePath.path stringByDeletingLastPathComponent]
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil];
    
    // write data
    return [fileManager moveItemAtURL:loadedFile toURL:filePath error: error];
}


@end
