import Foundation
import MudCore
import WebKit

/// Serves local image files for `mud-asset:` URLs requested by WKWebView.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView,
                 start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, code: 400, message: "Bad Request")
            return
        }

        // mud-asset:///absolute/path — the path is the file path.
        let filePath = url.path
        let fileURL = URL(fileURLWithPath: filePath)
        let ext = fileURL.pathExtension.lowercased()

        guard let mime = ImageDataURI.mimeTypes[ext] else {
            fail(urlSchemeTask, code: 403, message: "Forbidden")
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            fail(urlSchemeTask, code: 404, message: "Not Found")
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
            ]
        )!

        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView,
                 stop urlSchemeTask: any WKURLSchemeTask) {
        // Nothing to cancel — reads are synchronous.
    }

    private func fail(_ task: any WKURLSchemeTask, code: Int, message: String) {
        let response = HTTPURLResponse(
            url: task.request.url!,
            statusCode: code,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        )!
        task.didReceive(response)
        task.didReceive(Data(message.utf8))
        task.didFinish()
    }
}
