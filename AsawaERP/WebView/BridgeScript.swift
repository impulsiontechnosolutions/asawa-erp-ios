//
//  BridgeScript.swift
//  AsawaERP
//
//  The JavaScript that gets injected at document end into every page of the
//  ERPNext site. Mirrors Android's injectJsBridge() so the iOS app captures
//  the same `frappe.session.user`, the same logout event, and the same
//  blob:-URL download interception.
//
//  Native side handles these message names (registered in WebViewController):
//    • asawaSetUser           ─ string  — sets logged-in user email
//    • asawaLogout            ─ null    — user clicked logout
//    • asawaBlobChunkStart    ─ {token, filename, mime, totalChunks}
//    • asawaBlobChunkAppend   ─ {token, index, base64}
//    • asawaBlobChunkFinish   ─ {token}
//

import Foundation

enum BridgeScript {

    static let javaScript: String = """
    (function () {
      try {
        // ── 1. Capture logged-in user and hook logout (parity with Android) ──
        if (window.frappe) {
          try {
            if (frappe.session && frappe.session.user) {
              window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.asawaSetUser &&
                window.webkit.messageHandlers.asawaSetUser.postMessage(
                  String(frappe.session.user));
            }
          } catch (e) {}

          try {
            if (frappe.app && typeof frappe.app.logout === 'function'
                && !window.__asawaLogoutHooked) {
              window.__asawaLogoutHooked = true;
              var __origLogout = frappe.app.logout;
              frappe.app.logout = function () {
                try {
                  window.webkit && window.webkit.messageHandlers &&
                    window.webkit.messageHandlers.asawaLogout &&
                    window.webkit.messageHandlers.asawaLogout.postMessage(null);
                } catch (e) {}
                return __origLogout.apply(this, arguments);
              };
            }
          } catch (e) {}
        }

        // ── 2. blob: URL download interception (parity with Android) ──
        if (!window.__asawaBlobHooked) {
          window.__asawaBlobHooked = true;

          var CHUNK_SIZE = 256 * 1024; // 256 KB per native message

          function extFromMime(m) {
            var map = {
              'application/pdf': '.pdf',
              'text/csv': '.csv',
              'application/vnd.ms-excel': '.xls',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx',
              'application/zip': '.zip',
              'text/plain': '.txt',
              'application/json': '.json'
            };
            return map[m] || '';
          }

          async function blobToBase64Chunks(blob) {
            var buf = await blob.arrayBuffer();
            var bytes = new Uint8Array(buf);
            var binary = '';
            var step = 0x8000;
            for (var i = 0; i < bytes.length; i += step) {
              binary += String.fromCharCode.apply(null,
                bytes.subarray(i, Math.min(i + step, bytes.length)));
            }
            var b64 = btoa(binary);
            var chunks = [];
            for (var j = 0; j < b64.length; j += CHUNK_SIZE) {
              chunks.push(b64.slice(j, j + CHUNK_SIZE));
            }
            return chunks;
          }

          async function downloadBlobUrl(href, name) {
            try {
              var resp = await fetch(href);
              var blob = await resp.blob();
              var mime = blob.type || 'application/octet-stream';
              var filename = (name && name.trim()) ||
                             ((document.title || 'download') + extFromMime(mime));

              var token = Math.random().toString(36).slice(2) +
                          Date.now().toString(36);

              var chunks = await blobToBase64Chunks(blob);

              window.webkit.messageHandlers.asawaBlobChunkStart.postMessage({
                token: token, filename: filename, mime: mime,
                totalChunks: chunks.length
              });

              for (var i = 0; i < chunks.length; i++) {
                window.webkit.messageHandlers.asawaBlobChunkAppend.postMessage({
                  token: token, index: i, base64: chunks[i]
                });
              }

              window.webkit.messageHandlers.asawaBlobChunkFinish.postMessage({
                token: token
              });
            } catch (e) { /* swallow */ }
          }

          // Click handler — intercept <a href="blob:...">
          document.addEventListener('click', function (ev) {
            var a = ev.target && ev.target.closest && ev.target.closest('a[href]');
            if (!a) return;
            var href = a.getAttribute('href') || '';
            if (href.indexOf('blob:') === 0) {
              ev.preventDefault();
              ev.stopPropagation();
              downloadBlobUrl(href, a.getAttribute('download') || '');
            }
          }, true);

          // window.open with blob: URL — same redirect.
          (function () {
            var __origOpen = window.open;
            window.open = function (u, t, f) {
              if (typeof u === 'string' && u.indexOf('blob:') === 0) {
                downloadBlobUrl(u, '');
                return null;
              }
              return __origOpen.apply(window, arguments);
            };
          })();
        }
      } catch (e) { /* never throw out of injected JS */ }
    })();
    """
}
