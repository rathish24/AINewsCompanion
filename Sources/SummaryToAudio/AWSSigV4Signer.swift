import Foundation
import CryptoKit

/// Minimal AWS Signature Version 4 signer for AWS service REST/JSON APIs (Polly, Translate).
/// Based on AWS SigV4 process: https://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
struct AWSSigV4Signer {
    struct Credentials: Sendable {
        let accessKeyId: String
        let secretAccessKey: String
        let sessionToken: String?
    }

    struct SigningContext: Sendable {
        let service: String
        let region: String
    }

    static func sign(
        request: inout URLRequest,
        body: Data,
        credentials: Credentials,
        context: SigningContext,
        date: Date = Date()
    ) throws {
        guard let url = request.url,
              let host = url.host,
              let method = request.httpMethod else {
            throw NSError(domain: "AWSSigV4Signer", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URLRequest for signing"])
        }

        // Ensure required headers exist before canonicalization
        let amzDate = iso8601BasicTimestamp(date)
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        if let token = credentials.sessionToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Amz-Security-Token")
        }

        let payloadHash = sha256Hex(body)
        request.setValue(payloadHash, forHTTPHeaderField: "X-Amz-Content-Sha256")

        let (canonicalRequest, signedHeaders) = try canonicalRequestString(url: url, method: method, headers: request.allHTTPHeaderFields ?? [:], payloadHash: payloadHash)
        let dateStamp = yyyymmdd(date)
        let scope = "\(dateStamp)/\(context.region)/\(context.service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Hex(canonicalRequest.data(using: .utf8) ?? Data())
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secretAccessKey: credentials.secretAccessKey, dateStamp: dateStamp, region: context.region, service: context.service)
        let signature = hmacSHA256Hex(key: signingKey, message: stringToSign)

        let authorization = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    // MARK: - Canonical request

    private static func canonicalRequestString(
        url: URL,
        method: String,
        headers: [String: String],
        payloadHash: String
    ) throws -> (canonical: String, signedHeaders: String) {
        let canonicalURI = canonicalPath(url.path)
        let canonicalQuery = canonicalQueryString(url)

        // Lowercase header names, trim spaces, sort.
        var canonicalHeaders: [(String, String)] = headers
            .map { (name: $0.key.lowercased(), value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.0.isEmpty }

        canonicalHeaders.sort { $0.0 < $1.0 }

        // Combine duplicate headers by comma per RFC (rare here, but safe).
        var combined: [(String, String)] = []
        for (k, v) in canonicalHeaders {
            if let last = combined.last, last.0 == k {
                combined[combined.count - 1] = (k, "\(last.1),\(v)")
            } else {
                combined.append((k, v.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)))
            }
        }

        let canonicalHeadersString = combined
            .map { "\($0.0):\($0.1)\n" }
            .joined()

        let signedHeaders = combined.map { $0.0 }.joined(separator: ";")

        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQuery,
            canonicalHeadersString,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        return (canonicalRequest, signedHeaders)
    }

    private static func canonicalPath(_ path: String) -> String {
        // SigV4 expects a normalized, URI-encoded path (RFC3986).
        let p = path.isEmpty ? "/" : (path.hasPrefix("/") ? path : "/\(path)")
        let parts = p.split(separator: "/", omittingEmptySubsequences: false)
        let encoded = parts.map { seg in
            seg.addingPercentEncoding(withAllowedCharacters: .awsSigV4PathAllowed) ?? String(seg)
        }
        // Preserve leading slash by joining components; split above keeps an empty first element when path starts with "/".
        let joined = encoded.joined(separator: "/")
        return joined.isEmpty ? "/" : joined
    }

    private static func canonicalQueryString(_ url: URL) -> String {
        guard var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        let items = (comp.percentEncodedQueryItems ?? comp.queryItems ?? [])
        let encoded: [(String, String)] = items.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: .awsSigV4QueryAllowed) ?? item.name
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: .awsSigV4QueryAllowed) ?? (item.value ?? "")
            return (name, value)
        }
        let sorted = encoded.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        comp.percentEncodedQuery = nil
        return sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    // MARK: - Key derivation & hashing

    private static func deriveSigningKey(secretAccessKey: String, dateStamp: String, region: String, service: String) -> Data {
        let kSecret = Data(("AWS4" + secretAccessKey).utf8)
        let kDate = hmacSHA256(key: kSecret, message: dateStamp)
        let kRegion = hmacSHA256(key: kDate, message: region)
        let kService = hmacSHA256(key: kRegion, message: service)
        let kSigning = hmacSHA256(key: kService, message: "aws4_request")
        return kSigning
    }

    private static func hmacSHA256(key: Data, message: String) -> Data {
        let keySym = SymmetricKey(data: key)
        let sig = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: keySym)
        return Data(sig)
    }

    private static func hmacSHA256Hex(key: Data, message: String) -> String {
        let data = hmacSHA256(key: key, message: message)
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Dates

    private static func iso8601BasicTimestamp(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return fmt.string(from: date)
    }

    private static func yyyymmdd(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyyMMdd"
        return fmt.string(from: date)
    }
}

private extension CharacterSet {
    /// Allowed characters for canonical query encoding. AWS requires RFC3986 (space as %20, not '+').
    static let awsSigV4QueryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.~")
        return set
    }()

    /// Allowed characters for canonical path segment encoding (keep unreserved + '/').
    static let awsSigV4PathAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-_.~")
        return set
    }()
}

