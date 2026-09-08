import XCTest
import CryptoKit
@testable import Rolecall

final class BoardSignatureTests: XCTestCase {

    func testHexStringDecoding() {
        XCTAssertEqual(Data(hexString: "00ff10"), Data([0x00, 0xff, 0x10]))
        XCTAssertEqual(Data(hexString: "FF"), Data([0xff]))
        XCTAssertNil(Data(hexString: "zz"))
    }

    func testValidSignaturePasses_tamperFails_wrongKeyFails() {
        let key = Curve25519.Signing.PrivateKey()
        let keyHex = key.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        let board = Data("""
        {"generated_utc":1788800000.0,"count":1,"roles":[]}
        """.utf8)
        let sig = try! key.signature(for: board)
        let sigHex = sig.map { String(format: "%02x", $0) }.joined()

        XCTAssertTrue(BoardSignature.isValid(board: board, signatureHex: sigHex, keyHex: keyHex))
        XCTAssertTrue(BoardSignature.isValid(board: board, signatureHex: "  \(sigHex)\n", keyHex: keyHex),
                      "whitespace around the hex is tolerated")

        // tampered board
        XCTAssertFalse(BoardSignature.isValid(board: board + Data([0x20]), signatureHex: sigHex, keyHex: keyHex))
        // wrong key
        let otherKeyHex = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertFalse(BoardSignature.isValid(board: board, signatureHex: sigHex, keyHex: otherKeyHex))
        // garbage signature
        XCTAssertFalse(BoardSignature.isValid(board: board, signatureHex: "deadbeef", keyHex: keyHex))
        XCTAssertFalse(BoardSignature.isValid(board: board, signatureHex: "", keyHex: keyHex))
    }

    func testAppPublicKeyIsWellFormed() {
        let bytes = Data(hexString: BoardSignature.publicKeyHex)
        XCTAssertEqual(bytes?.count, 32, "the embedded Ed25519 public key must be 32 bytes")
        XCTAssertNotNil(try? Curve25519.Signing.PublicKey(rawRepresentation: bytes!))
    }

    /// P0-8: the vendored Python Ed25519 (`engine/ed25519.py`) and Apple's CryptoKit must
    /// agree, or a board the engine signs would fail verification on device (or worse).
    /// The fixture is a `(pubkey, message, signature)` triple the Python impl produced;
    /// this verifies it with CryptoKit — the same call `BoardSignature.isValid` makes.
    func testEd25519CrossImplementationFixture() throws {
        struct Fixture: Decodable {
            let public_key_hex: String
            let message_utf8: String
            let signature_hex: String
        }
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "ed25519_cross_impl", withExtension: "json"),
            "cross-impl fixture missing from the test bundle")
        let fx = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let message = Data(fx.message_utf8.utf8)

        // The real path: BoardSignature.isValid, with the fixture's key.
        XCTAssertTrue(
            BoardSignature.isValid(board: message,
                                   signatureHex: fx.signature_hex,
                                   keyHex: fx.public_key_hex),
            "Python-produced signature must verify under CryptoKit")

        // Direct CryptoKit check, and a tamper negative.
        let keyBytes = try XCTUnwrap(Data(hexString: fx.public_key_hex))
        let sigBytes = try XCTUnwrap(Data(hexString: fx.signature_hex))
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
        XCTAssertEqual(sigBytes.count, 64)
        XCTAssertTrue(key.isValidSignature(sigBytes, for: message))
        XCTAssertFalse(key.isValidSignature(sigBytes, for: message + Data([0x21])),
                       "a one-byte change to the message must break the signature")
    }
}
