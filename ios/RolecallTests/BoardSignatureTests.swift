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
}
