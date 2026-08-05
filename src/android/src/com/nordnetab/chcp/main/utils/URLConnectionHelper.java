package com.nordnetab.chcp.main.utils;

import java.io.IOException;
import java.net.URL;
import java.net.URLConnection;
import java.util.Map;

/**
 * Created by Nikolay Demyankov on 03.06.16.
 * <p/>
 * Helper class to work with URLConnection
 */
public class URLConnectionHelper {

    // Larger timeouts: Appery updates often contain 1000+ files over mobile networks
    private static final int CONNECTION_TIMEOUT = 60000;

    private static final int READ_TIMEOUT = 120000;

    /**
     * Create URLConnection instance.
     *
     * @param url            to what url
     * @param requestHeaders additional request headers
     * @return connection instance
     * @throws IOException when url is invalid or failed to establish connection
     */
    public static URLConnection createConnectionToURL(final String url, final Map<String, String> requestHeaders) throws IOException {
        final URL connectionURL = URLUtility.stringToUrl(url);
        if (connectionURL == null) {
            throw new IOException("Invalid url format: " + url);
        }

        final URLConnection urlConnection = connectionURL.openConnection();
        urlConnection.setConnectTimeout(CONNECTION_TIMEOUT);
        urlConnection.setReadTimeout(READ_TIMEOUT);

        if (requestHeaders != null) {
            for (final Map.Entry<String, String> entry : requestHeaders.entrySet()) {
                urlConnection.setRequestProperty(entry.getKey(), entry.getValue());
            }
        }

        return urlConnection;
    }

}
