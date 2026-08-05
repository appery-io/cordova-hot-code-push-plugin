package com.nordnetab.chcp.main.network;

import android.util.Log;

import com.nordnetab.chcp.main.model.ManifestFile;
import com.nordnetab.chcp.main.utils.FilesUtility;
import com.nordnetab.chcp.main.utils.MD5;
import com.nordnetab.chcp.main.utils.Paths;
import com.nordnetab.chcp.main.utils.URLConnectionHelper;
import com.nordnetab.chcp.main.utils.URLUtility;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URLConnection;
import java.util.List;
import java.util.Map;

/**
 * Helper class to download files with retries.
 * Large Appery manifests (1000+ files) often fail intermittently without retries.
 */
public class FileDownloader {

    private static final int MAX_RETRIES = 3;
    private static final long RETRY_DELAY_MS = 500;

    /**
     * Download list of files.
     * Full url to the file is constructed from the contentFolderUrl and ManifestFile name.
     * For each downloaded file we check its hash against ManifestFile#hash.
     * Download stops on any error after retries are exhausted.
     */
    public static void downloadFiles(final String downloadFolder,
                                     final String contentFolderUrl,
                                     final List<ManifestFile> files,
                                     final Map<String, String> requestHeaders) throws Exception {
        for (ManifestFile file : files) {
            String fileUrl = URLUtility.construct(contentFolderUrl, file.name);
            String filePath = Paths.get(downloadFolder, file.name);
            downloadWithRetry(fileUrl, filePath, file.hash, requestHeaders);
        }
    }

    private static void downloadWithRetry(final String urlFrom,
                                          final String filePath,
                                          final String checkSum,
                                          final Map<String, String> requestHeaders) throws Exception {
        Exception lastError = null;
        for (int attempt = 1; attempt <= MAX_RETRIES; attempt++) {
            try {
                download(urlFrom, filePath, checkSum, requestHeaders);
                return;
            } catch (Exception e) {
                lastError = e;
                Log.w("CHCP", "Download attempt " + attempt + "/" + MAX_RETRIES + " failed for " + urlFrom + ": " + e.getMessage());
                try {
                    FilesUtility.delete(new File(filePath));
                } catch (Exception ignored) {
                }
                if (attempt < MAX_RETRIES) {
                    Thread.sleep(RETRY_DELAY_MS * attempt);
                }
            }
        }
        throw lastError;
    }

    /**
     * Download file from server, save it on the disk and check his hash.
     */
    public static void download(final String urlFrom,
                                final String filePath,
                                final String checkSum,
                                final Map<String, String> requestHeaders) throws Exception {
        Log.d("CHCP", "Loading file: " + urlFrom);
        final MD5 md5 = new MD5();

        final File downloadFile = new File(filePath);
        FilesUtility.delete(downloadFile);
        FilesUtility.ensureDirectoryExists(downloadFile.getParentFile());

        final URLConnection connection = URLConnectionHelper.createConnectionToURL(urlFrom, requestHeaders);
        if (connection instanceof HttpURLConnection) {
            final HttpURLConnection http = (HttpURLConnection) connection;
            http.setInstanceFollowRedirects(true);
            final int code = http.getResponseCode();
            if (code < 200 || code >= 300) {
                throw new IOException("Failed to download file " + urlFrom + ": HTTP " + code);
            }
        }

        final InputStream input = new BufferedInputStream(connection.getInputStream());
        final OutputStream output = new BufferedOutputStream(new FileOutputStream(filePath, false));

        try {
            final byte data[] = new byte[8192];
            int count;
            while ((count = input.read(data)) != -1) {
                output.write(data, 0, count);
                md5.write(data, count);
            }
            output.flush();
        } finally {
            try {
                output.close();
            } catch (Exception ignored) {
            }
            try {
                input.close();
            } catch (Exception ignored) {
            }
        }

        final String downloadedFileHash = md5.calculateHash();
        if (!downloadedFileHash.equals(checkSum)) {
            throw new IOException("File is corrupted: checksum " + checkSum + " doesn't match hash " + downloadedFileHash + " of the downloaded file");
        }
    }
}
