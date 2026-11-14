// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Security

/// Par de claves RSA de la sesión. La moto envía su HUID en claro; el teléfono lo devuelve
/// "cifrado con la clave privada" (firma PKCS#1 v1.5 sin DigestInfo) junto con la clave pública.
final class RsaKeys {
    static let shared = RsaKeys()

    private var privateKey: SecKey?
    private(set) var publicKeyBase64: String = ""
    private(set) var bits: Int = 0

    private init() {
        for size in [1024, 2048] {
            let attrs: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: size,
            ]
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
                  let pub = SecKeyCopyPublicKey(key),
                  let pkcs1 = SecKeyCopyExternalRepresentation(pub, nil) as Data? else {
                continue
            }
            privateKey = key
            publicKeyBase64 = RsaKeys.subjectPublicKeyInfo(pkcs1).base64EncodedString()
            bits = size
            break
        }
    }

    func signHuid(_ huid: String) -> String {
        guard let key = privateKey else { return "" }
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(
            key, .rsaSignatureDigestPKCS1v15Raw, Data(huid.utf8) as CFData, &error
        ) as Data? else {
            return ""
        }
        return sig.base64EncodedString()
    }

    private static func derLength(_ n: Int) -> [UInt8] {
        if n < 128 { return [UInt8(n)] }
        if n < 256 { return [0x81, UInt8(n)] }
        return [0x82, UInt8(n >> 8), UInt8(n & 0xFF)]
    }

    /// iOS exporta la clave pública en PKCS#1; Android (y la moto) esperan X.509 SubjectPublicKeyInfo.
    private static func subjectPublicKeyInfo(_ pkcs1: Data) -> Data {
        let algorithm: [UInt8] = [
            0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00,
        ]
        let bitString: [UInt8] = [0x03] + derLength(pkcs1.count + 1) + [0x00] + [UInt8](pkcs1)
        let body = algorithm + bitString
        return Data([0x30] + derLength(body.count) + body)
    }
}
