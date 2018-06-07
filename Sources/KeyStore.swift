// Copyright © 2017-2018 ZLA.
//
// This file is part of ZLA. The full ZLA copyright notice, including
// terms governing use, modification, and redistribution, is contained in the
// file LICENSE at the root of the source code distribution tree.

import Foundation
import ZillaCore

public protocol KeystoreDataDelegate: class {
    func save(key: KeystoreKey) throws
    func delete(account: Account) throws
    func getKeystoreKeys() -> [KeystoreKey]
}

/// Manages directories of key and wallet files and presents them as accounts.
public final class KeyStore {
    /// Delegate to save, delete, load account information.
    public weak var delegate: KeystoreDataDelegate?

    /// Dictionary of accounts by address.
    private var accountsByAddress = [Address: Account]()

    /// Dictionary of keys by address.
    private var keysByAddress = [Address: KeystoreKey]()

    /// Creates a `KeyStore` for the given directory.
    public init(delegate: KeystoreDataDelegate) throws {
        self.delegate = delegate
        try load()
    }

    private func load() throws {
        if let keys = delegate?.getKeystoreKeys() {
            for key in keys {
                keysByAddress[key.address] = key
                let account = Account(address: key.address, type: key.type)
                accountsByAddress[key.address] = account
            }
        }
    }

    /// List of accounts.
    public var accounts: [Account] {
        return Array(accountsByAddress.values)
    }

    /// Retrieves an account for the given address, if it exists.
    public func account(for address: Address) -> Account? {
        return accountsByAddress[address]
    }

    /// Retrieves a key for the given address, if it exists.
    public func key(for address: Address) -> KeystoreKey? {
        return keysByAddress[address]
    }

    /// Creates a new account.
    public func createAccount(password: String, type: AccountType) throws -> Account {
        let key = try KeystoreKey(password: password, type: type)
        keysByAddress[key.address] = key

        let account = Account(address: key.address, type: type)
        try save(account: account)
        accountsByAddress[key.address] = account
        return account
    }

    /// Imports an encrypted JSON key.
    ///
    /// - Parameters:
    ///   - key: key to import
    ///   - password: key password
    ///   - newPassword: password to use for the imported key
    /// - Returns: new account
    public func `import`(json: Data, password: String, newPassword: String) throws -> Account {
        let key = try JSONDecoder().decode(KeystoreKey.self, from: json)
        if self.account(for: key.address) != nil {
            throw Error.accountAlreadyExists
        }

        var privateKey = try key.decrypt(password: password)
        defer {
            privateKey.resetBytes(in: 0..<privateKey.count)
        }

        let newKey = try KeystoreKey(password: newPassword, key: privateKey)
        keysByAddress[newKey.address] = newKey

        let account = Account(address: newKey.address, type: key.type)
        try save(account: account)
        accountsByAddress[newKey.address] = account

        return account
    }

    /// Imports a wallet.
    ///
    /// - Parameters:
    ///   - mnemonic: wallet's mnemonic phrase
    ///   - passphrase: wallet's password
    ///   - derivationPath: wallet's derivation path
    ///   - encryptPassword: password to use for encrypting
    /// - Returns: new account
    public func `import`(mnemonic: String, passphrase: String = "", derivationPath: String = Wallet.defaultPath, encryptPassword: String) throws -> Account {
        if !Mnemonic.isValid(mnemonic) {
            throw Error.invalidMnemonic
        }

        let wallet = Wallet(mnemonic: mnemonic, passphrase: passphrase, path: derivationPath)
        let address = wallet.getKey(at: 0).address
        if self.account(for: address) != nil {
            throw Error.accountAlreadyExists
        }

        let newKey = try KeystoreKey(password: encryptPassword, mnemonic: mnemonic, passphrase: passphrase, derivationPath: derivationPath)
        keysByAddress[newKey.address] = newKey

        let account = Account(address: address, type: .hierarchicalDeterministicWallet)
        try save(account: account)
        accountsByAddress[address] = account

        return account
    }

    /// Exports an account as JSON data.
    ///
    /// - Parameters:
    ///   - account: account to export
    ///   - password: account password
    ///   - newPassword: password to use for exported key
    /// - Returns: encrypted JSON key
    public func export(account: Account, password: String, newPassword: String) throws -> Data {
        guard let key = keysByAddress[account.address] else {
            fatalError("Missing account key")
        }

        var privateKey = try key.decrypt(password: password)
        defer {
            privateKey.resetBytes(in: 0..<privateKey.count)
        }

        let newKey: KeystoreKey
        switch key.type {
        case .encryptedKey:
            newKey = try KeystoreKey(password: newPassword, key: privateKey)
        case .hierarchicalDeterministicWallet:
            guard let string = String(data: privateKey, encoding: .ascii) else {
                throw EncryptError.invalidMnemonic
            }
            newKey = try KeystoreKey(password: newPassword, mnemonic: string, passphrase: key.passphrase, derivationPath: key.derivationPath)
        }
        return try JSONEncoder().encode(newKey)
    }

    /// Exports an account as private key data.
    ///
    /// - Parameters:
    ///   - account: account to export
    ///   - password: account password
    /// - Returns: private key data
    public func exportPrivateKey(account: Account, password: String) throws -> Data {
        guard let key = keysByAddress[account.address] else {
            fatalError("Missing account key")
        }

        var privateKey = try key.decrypt(password: password)
        defer {
            privateKey.resetBytes(in: 0..<privateKey.count)
        }

        switch key.type {
        case .encryptedKey:
            return privateKey
        case .hierarchicalDeterministicWallet:
            guard let string = String(data: privateKey, encoding: .ascii) else {
                throw EncryptError.invalidMnemonic
            }
            return Wallet(mnemonic: string, passphrase: key.passphrase, path: key.derivationPath).getKey(at: 0).privateKey
        }
    }

    /// Exports an account as a mnemonic phrase.
    ///
    /// - Parameters:
    ///   - account: account to export
    ///   - password: account password
    /// - Returns: private key data
    public func exportMnemonic(account: Account, password: String) throws -> String {
        guard let key = keysByAddress[account.address] else {
            fatalError("Missing account key")
        }

        var privateKey = try key.decrypt(password: password)
        defer {
            privateKey.resetBytes(in: 0..<privateKey.count)
        }

        switch key.type {
        case .encryptedKey:
            throw EncryptError.invalidMnemonic
        case .hierarchicalDeterministicWallet:
            guard let string = String(data: privateKey, encoding: .ascii) else {
                throw EncryptError.invalidMnemonic
            }
            if string.hasSuffix("\0") {
                return String(string.dropLast())
            } else {
                return string
            }
        }
    }

    /// Updates the password of an existing account.
    ///
    /// - Parameters:
    ///   - account: account to update
    ///   - password: current password
    ///   - newPassword: new password
    public func update(account: Account, password: String, newPassword: String) throws {
        guard let key = keysByAddress[account.address] else {
            fatalError("Missing account key")
        }

        var privateKey = try key.decrypt(password: password)
        defer {
            privateKey.resetBytes(in: 0..<privateKey.count)
        }

        let newKey: KeystoreKey
        switch key.type {
        case .encryptedKey:
            newKey = try KeystoreKey(password: newPassword, key: privateKey)
        case .hierarchicalDeterministicWallet:
            guard let string = String(data: privateKey, encoding: .ascii) else {
                throw EncryptError.invalidMnemonic
            }
            newKey = try KeystoreKey(password: newPassword, mnemonic: string, passphrase: key.passphrase)
        }
        keysByAddress[newKey.address] = newKey
    }

    /// Deletes an account including its key if the password is correct.
    public func delete(account: Account, password: String) throws {
        guard let key = keysByAddress[account.address] else {
            fatalError("Missing account key")
        }

        var privateKey = try key.decrypt(password: password)
        defer {
            privateKey.resetBytes(in: 0..<privateKey.count)
        }

        keysByAddress[account.address] = nil

        try delegate?.delete(account: account)
        accountsByAddress[account.address] = nil
    }

    /// Calculates a ECDSA signature for the give hash.
    ///
    /// - Parameters:
    ///   - data: hash to sign
    ///   - account: account to use for signing
    ///   - password: account password
    /// - Returns: signature
    /// - Throws: `DecryptError`, `Secp256k1Error`, or `KeyStore.Error`
    public func signHash(_ data: Data, account: Account, password: String) throws -> Data {
        guard let key = keysByAddress[account.address] else {
            throw KeyStore.Error.accountNotFound
        }
        return try key.sign(hash: data, password: password)
    }

    /// Signs an array of hashes with the given password.
    ///
    /// - Parameters:
    ///   - hashes: array of hashes to sign
    ///   - account: account to use for signing
    ///   - password: key password
    /// - Returns: array of signatures
    /// - Throws: `DecryptError` or `Secp256k1Error` or `KeyStore.Error`
    public func signHashes(_ data: [Data], account: Account, password: String) throws -> [Data] {
        guard let key = keysByAddress[account.address] else {
            throw KeyStore.Error.accountNotFound
        }
        return try key.signHashes(data, password: password)
    }

    /// Saves the account to the given directory.
    private func save(account: Account) throws {
        guard let key = keysByAddress[account.address] else {
            fatalError("Missing account key")
        }
        try delegate?.save(key: key)
    }

    private func save(key: KeystoreKey, to url: URL) throws {
        let json = try JSONEncoder().encode(key)
        try json.write(to: url, options: [.atomicWrite])
    }
}
