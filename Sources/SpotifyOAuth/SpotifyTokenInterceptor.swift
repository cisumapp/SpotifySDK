import Foundation

/// The JavaScript interceptor injected into WKWebView at document start.
/// Hooks fetch, XHR, JSON.parse, postMessage, and DOM scanning to capture
/// accessToken and clientToken from the Spotify Web Player.
package let spotifyTokenInterceptorJS = """
const originalFetch = window.fetch;

// Helper to log to Swift
function swiftLog(message) {
    window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'DEBUG', payload: { msg: message } });
}

window.fetch = async function(...args) {
    let requestUrl = '';
    if (typeof args[0] === 'string') {
        requestUrl = args[0];
    } else if (args[0] && typeof args[0] === 'object' && args[0].url) {
        requestUrl = args[0].url;
    }

    if (requestUrl && (requestUrl.includes('/api/token') || requestUrl.includes('getAccessToken') || requestUrl.includes('clienttoken'))) {
        swiftLog('FETCH Outgoing: ' + requestUrl);
    }

    const response = await originalFetch.apply(this, args);

    if (requestUrl) {
        if (requestUrl.includes('token') || requestUrl.includes('web-player') || requestUrl.includes('api/token')) {
            const clone = response.clone();
            clone.text().then(text => {
                if (requestUrl.includes('api/token')) {
                    swiftLog('FETCH Response (' + requestUrl + '): ' + text.substring(0, 200));
                }
                try {
                    const data = JSON.parse(text);
                    if (data.accessToken || data.access_token) {
                        window.webkit.messageHandlers.spotifyTokenHandler.postMessage({
                            type: 'ACCESS_TOKEN',
                            payload: data
                        });
                    }
                    if (data.granted_token && data.granted_token.token) {
                        window.webkit.messageHandlers.spotifyTokenHandler.postMessage({
                            type: 'CLIENT_TOKEN',
                            payload: data
                        });
                    }
                } catch(e) {}
            }).catch(e => {});
        }
    }
    return response;
};

const originalXHR = window.XMLHttpRequest;
window.XMLHttpRequest = function() {
    const xhr = new originalXHR();
    const originalOpen = xhr.open;
    let currentUrl = '';
    
    xhr.open = function(method, url) {
        currentUrl = url;
        if (url && (url.includes('/api/token') || url.includes('clienttoken'))) {
            swiftLog('XHR Outgoing: ' + url);
        }
        return originalOpen.apply(xhr, arguments);
    };
    
    xhr.addEventListener('load', function() {
        if (!currentUrl) return;
        if (currentUrl.includes('api/token')) {
            swiftLog('XHR Response (' + currentUrl + '): ' + (xhr.responseText ? xhr.responseText.substring(0, 200) : 'EMPTY'));
        }
        try {
            if (currentUrl.includes('token') || currentUrl.includes('web-player')) {
                const data = JSON.parse(xhr.responseText);
                if (data.accessToken || data.access_token) {
                    window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'ACCESS_TOKEN', payload: data });
                }
                if (data.granted_token && data.granted_token.token) {
                    window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'CLIENT_TOKEN', payload: data });
                }
            }
        } catch(e) {}
    });
    
    return xhr;
};

// Also try to find it in DOM just in case
document.addEventListener('DOMContentLoaded', () => {
    // 1. Check session script
    const sessionScript = document.getElementById('session');
    if (sessionScript) {
        swiftLog('Found #session script in DOM');
        try {
            const data = JSON.parse(sessionScript.textContent);
            if (data.accessToken) {
                window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'ACCESS_TOKEN', payload: data });
            }
        } catch(e) {}
    }
    
    // 2. Scan all scripts for a hardcoded token (Server-Side Rendered config)
    const scripts = document.querySelectorAll('script');
    for (let script of scripts) {
        if (script.textContent && script.textContent.includes('accessToken')) {
            swiftLog('Found accessToken string inside a script tag!');
            const match = script.textContent.match(/"accessToken"s*:s*"([^"]+)"/);
            if (match && match[1]) {
                window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'ACCESS_TOKEN', payload: { accessToken: match[1] } });
            }
        }
    }
});

// The Ultimate Wiretap: Hook JSON.parse
const originalJSONParse = JSON.parse;
JSON.parse = function(text, reviver) {
    const result = originalJSONParse.call(this, text, reviver);
    try {
        if (result && typeof result === 'object') {
            if (result.accessToken && typeof result.accessToken === 'string' && result.accessToken.length > 20) {
                swiftLog('Intercepted accessToken via JSON.parse hook!');
                window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'ACCESS_TOKEN', payload: result });
            }
            if (result.granted_token && result.granted_token.token) {
                window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'CLIENT_TOKEN', payload: result });
            }
        }
    } catch(e) {}
    return result;
};

// The absolute Nuke: Regex Scanner for the exact Access Token signature
const tokenRegex = /BQC[a-zA-Z0-9_\\-]{150,}/;
function scanStringForToken(str) {
    if (!str) return false;
    const match = str.match(tokenRegex);
    if (match && match[0]) return match[0];
    return null;
}

setInterval(() => {
    let foundToken = null;
    foundToken = scanStringForToken(document.documentElement.innerHTML);
    if (!foundToken) foundToken = scanStringForToken(JSON.stringify(localStorage));
    if (!foundToken) foundToken = scanStringForToken(JSON.stringify(sessionStorage));
    if (!foundToken) foundToken = scanStringForToken(document.cookie);
    
    if (foundToken) {
        window.webkit.messageHandlers.spotifyTokenHandler.postMessage({ type: 'ACCESS_TOKEN', payload: { accessToken: foundToken } });
    }
}, 2000);
"""

/// WKContentRuleList JSON to block images, CSS, fonts, and media during extraction.
package let spotifyContentBlockRules = """
[{
    "trigger": { "url-filter": ".*", "resource-type": ["image", "style-sheet", "font", "media"] },
    "action": { "type": "block" }
}]
"""
