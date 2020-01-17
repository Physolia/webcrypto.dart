import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:webcrypto/webcrypto.dart';
import 'ffibonacci_chunked_stream.dart';
import 'utils.dart';
import 'lipsum.dart';

List<int> _optionalBase64Decode(dynamic data) =>
    data == null ? null : base64.decode(data as String);

Map<String, dynamic> _optionalStringMapDecode(dynamic data) =>
    data == null ? null : (data as Map).cast<String, dynamic>();

String _optionalBase64Encode(List<int> data) =>
    data == null ? null : base64.encode(data);

@sealed
class TestCase {
  final String name;

  // Obtain a keyPair from import or key generation
  final Map<String, dynamic> generateKeyParams;
  final List<int> privateRawKeyData;
  final List<int> privatePkcs8KeyData;
  final Map<String, dynamic> privateJsonWebKeyData;
  final List<int> publicRawKeyData;
  final List<int> publicSpkiKeyData;
  final Map<String, dynamic> publicJsonWebKeyData;

  // Plaintext to be signed, (always required)
  final List<int> plaintext;
  // Signature to be verified (invalid, if generateKeyParams != null)
  final List<int> signature;
  // Ciphertext of plaintext (invalid, if generateKeyParams != null)
  final List<int> ciphertext;

  // Parameters for key import (always required)
  final Map<String, dynamic> importKeyParams;

  // Parameters for sign/verify (required, if there is a signature)
  final Map<String, dynamic> signVerifyParams;

  // Parameters for encrypt/decrypt (required, if there is a ciphertext)
  final Map<String, dynamic> encryptDecryptParams;

  TestCase(
    this.name, {
    this.generateKeyParams,
    this.privateRawKeyData,
    this.privatePkcs8KeyData,
    this.privateJsonWebKeyData,
    this.publicRawKeyData,
    this.publicSpkiKeyData,
    this.publicJsonWebKeyData,
    this.plaintext,
    this.signature,
    this.ciphertext,
    this.importKeyParams,
    this.signVerifyParams,
    this.encryptDecryptParams,
  });

  factory TestCase.fromJson(Map json) {
    return TestCase(
      json['name'] as String,
      generateKeyParams: _optionalStringMapDecode(json['generateKeyParams']),
      privateRawKeyData: _optionalBase64Decode(json['privateRawKeyData']),
      privatePkcs8KeyData: _optionalBase64Decode(json['privatePkcs8KeyData']),
      privateJsonWebKeyData:
          _optionalStringMapDecode(json['privateJsonWebKeyData']),
      publicRawKeyData: _optionalBase64Decode(json['publicRawKeyData']),
      publicSpkiKeyData: _optionalBase64Decode(json['publicSpkiKeyData']),
      publicJsonWebKeyData:
          _optionalStringMapDecode(json['publicJsonWebKeyData']),
      plaintext: _optionalBase64Decode(json['plaintext']),
      signature: _optionalBase64Decode(json['signature']),
      ciphertext: _optionalBase64Decode(json['ciphertext']),
      importKeyParams: _optionalStringMapDecode(json['importKeyParams']),
      signVerifyParams: _optionalStringMapDecode(json['signVerifyParams']),
      encryptDecryptParams:
          _optionalStringMapDecode(json['encryptDecryptParams']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'generateKeyParams': generateKeyParams,
      'privateRawKeyData': _optionalBase64Encode(privateRawKeyData),
      'privatePkcs8KeyData': _optionalBase64Encode(privatePkcs8KeyData),
      'privateJsonWebKeyData': privateJsonWebKeyData,
      'publicRawKeyData': _optionalBase64Encode(publicRawKeyData),
      'publicSpkiKeyData': _optionalBase64Encode(publicSpkiKeyData),
      'publicJsonWebKeyData': publicJsonWebKeyData,
      'plaintext': _optionalBase64Encode(plaintext),
      'signature': _optionalBase64Encode(signature),
      'ciphertext': _optionalBase64Encode(ciphertext),
      'importKeyParams': importKeyParams,
      'signVerifyParams': signVerifyParams,
      'encryptDecryptParams': encryptDecryptParams,
    }..removeWhere((_, v) => v == null);
  }
}

/// Function for importing pkcs8, spki, or raw key.
typedef ImportKeyFn<T> = Future<T> Function(
  List<int> keyData,
  Map<String, dynamic> keyImportParams,
);

/// Function for exporting pkcs8, spki or raw key.
typedef ExportKeyFn<T> = Future<List<int>> Function(T key);

/// Function for importing JWK key.
typedef ImportJsonWebKeyKeyFn<T> = Future<T> Function(
  Map<String, dynamic> jsonWebKeyData,
  Map<String, dynamic> keyImportParams,
);

/// Function for exporting JWK key.
typedef ExportJsonWebKeyKeyFn<T> = Future<Map<String, dynamic>> Function(T key);

/// Function for generating a [KeyPair].
typedef GenerateKeyPairFn<S, T> = Future<KeyPair<S, T>> Function(
  Map<String, dynamic> generateKeyPairParams,
);

/// Function for generating a key.
typedef GenerateKeyFn<T> = Future<T> Function(
  Map<String, dynamic> generateKeyPairParams,
);

/// Function for signing [data] using [key].
typedef SignBytesFn<T> = Future<List<int>> Function(
  T key,
  List<int> data,
  Map<String, dynamic> signParams,
);

/// Function for signing [data] using [key].
typedef SignStreamFn<T> = Future<List<int>> Function(
  T key,
  Stream<List<int>> data,
  Map<String, dynamic> signParams,
);

/// Function for verifying [data] using [key].
typedef VerifyBytesFn<T> = Future<bool> Function(
  T key,
  List<int> signature,
  List<int> data,
  Map<String, dynamic> verifyParams,
);

/// Function for verifying [data] using [key].
typedef VerifyStreamFn<T> = Future<bool> Function(
  T key,
  List<int> signature,
  Stream<List<int>> data,
  Map<String, dynamic> verifyParams,
);

/// Function for encrypting or a function for decrypting [data] using [key].
typedef EncryptOrDecryptBytesFn<T> = Future<List<int>> Function(
  T key,
  List<int> data,
  Map<String, dynamic> encryptOrDecryptParams,
);

/// Function for encrypting or a function for decrypting [data] using [key].
typedef EncryptOrDecryptStreamFn<T> = Stream<List<int>> Function(
  T key,
  Stream<List<int>> data,
  Map<String, dynamic> encryptOrDecryptParams,
);

class _KeyPair<S, T> implements KeyPair<S, T> {
  final S privateKey;
  final T publicKey;
  _KeyPair({this.privateKey, this.publicKey});
}

@sealed
class TestRunner<PrivateKey, PublicKey> {
  /// True, if private is a secret key and there is no public key.
  final bool _isSymmetric;

  final ImportKeyFn<PrivateKey> _importPrivateRawKey;
  final ExportKeyFn<PrivateKey> _exportPrivateRawKey;
  final ImportKeyFn<PrivateKey> _importPrivatePkcs8Key;
  final ExportKeyFn<PrivateKey> _exportPrivatePkcs8Key;
  final ImportJsonWebKeyKeyFn<PrivateKey> _importPrivateJsonWebKey;
  final ExportJsonWebKeyKeyFn<PrivateKey> _exportPrivateJsonWebKey;

  final ImportKeyFn<PublicKey> _importPublicRawKey;
  final ExportKeyFn<PublicKey> _exportPublicRawKey;
  final ImportKeyFn<PublicKey> _importPublicSpkiKey;
  final ExportKeyFn<PublicKey> _exportPublicSpkiKey;
  final ImportJsonWebKeyKeyFn<PublicKey> _importPublicJsonWebKey;
  final ExportJsonWebKeyKeyFn<PublicKey> _exportPublicJsonWebKey;

  final GenerateKeyPairFn<PrivateKey, PublicKey> _generateKeyPair;
  final SignBytesFn<PrivateKey> _signBytes;
  final SignStreamFn<PrivateKey> _signStream;
  final VerifyBytesFn<PublicKey> _verifyBytes;
  final VerifyStreamFn<PublicKey> _verifyStream;
  final EncryptOrDecryptBytesFn<PublicKey> _encryptBytes;
  final EncryptOrDecryptStreamFn<PublicKey> _encryptStream;
  final EncryptOrDecryptBytesFn<PrivateKey> _decryptBytes;
  final EncryptOrDecryptStreamFn<PrivateKey> _decryptStream;

  TestRunner._({
    @required bool isSymmetric,
    ImportKeyFn<PrivateKey> importPrivateRawKey,
    ExportKeyFn<PrivateKey> exportPrivateRawKey,
    ImportKeyFn<PrivateKey> importPrivatePkcs8Key,
    ExportKeyFn<PrivateKey> exportPrivatePkcs8Key,
    ImportJsonWebKeyKeyFn<PrivateKey> importPrivateJsonWebKey,
    ExportJsonWebKeyKeyFn<PrivateKey> exportPrivateJsonWebKey,
    ImportKeyFn<PublicKey> importPublicRawKey,
    ExportKeyFn<PublicKey> exportPublicRawKey,
    ImportKeyFn<PublicKey> importPublicSpkiKey,
    ExportKeyFn<PublicKey> exportPublicSpkiKey,
    ImportJsonWebKeyKeyFn<PublicKey> importPublicJsonWebKey,
    ExportJsonWebKeyKeyFn<PublicKey> exportPublicJsonWebKey,
    @required GenerateKeyPairFn<PrivateKey, PublicKey> generateKeyPair,
    SignBytesFn<PrivateKey> signBytes,
    SignStreamFn<PrivateKey> signStream,
    VerifyBytesFn<PublicKey> verifyBytes,
    VerifyStreamFn<PublicKey> verifyStream,
    EncryptOrDecryptBytesFn<PublicKey> encryptBytes,
    EncryptOrDecryptStreamFn<PublicKey> encryptStream,
    EncryptOrDecryptBytesFn<PrivateKey> decryptBytes,
    EncryptOrDecryptStreamFn<PrivateKey> decryptStream,
  })  : _isSymmetric = isSymmetric,
        _importPrivateRawKey = importPrivateRawKey,
        _exportPrivateRawKey = exportPrivateRawKey,
        _importPrivatePkcs8Key = importPrivatePkcs8Key,
        _exportPrivatePkcs8Key = exportPrivatePkcs8Key,
        _importPrivateJsonWebKey = importPrivateJsonWebKey,
        _exportPrivateJsonWebKey = exportPrivateJsonWebKey,
        _importPublicRawKey = importPublicRawKey,
        _exportPublicRawKey = exportPublicRawKey,
        _importPublicSpkiKey = importPublicSpkiKey,
        _exportPublicSpkiKey = exportPublicSpkiKey,
        _importPublicJsonWebKey = importPublicJsonWebKey,
        _exportPublicJsonWebKey = exportPublicJsonWebKey,
        _generateKeyPair = generateKeyPair,
        _signBytes = signBytes,
        _signStream = signStream,
        _verifyBytes = verifyBytes,
        _verifyStream = verifyStream,
        _encryptBytes = encryptBytes,
        _encryptStream = encryptStream,
        _decryptBytes = decryptBytes,
        _decryptStream = decryptStream {
    _validate();
  }

  /// Create [TestRunner] for an asymmetric primitive.
  static TestRunner<PrivateKey, PublicKey> asymmetric<PrivateKey, PublicKey>({
    ImportKeyFn<PrivateKey> importPrivateRawKey,
    ExportKeyFn<PrivateKey> exportPrivateRawKey,
    ImportKeyFn<PrivateKey> importPrivatePkcs8Key,
    ExportKeyFn<PrivateKey> exportPrivatePkcs8Key,
    ImportJsonWebKeyKeyFn<PrivateKey> importPrivateJsonWebKey,
    ExportJsonWebKeyKeyFn<PrivateKey> exportPrivateJsonWebKey,
    ImportKeyFn<PublicKey> importPublicRawKey,
    ExportKeyFn<PublicKey> exportPublicRawKey,
    ImportKeyFn<PublicKey> importPublicSpkiKey,
    ExportKeyFn<PublicKey> exportPublicSpkiKey,
    ImportJsonWebKeyKeyFn<PublicKey> importPublicJsonWebKey,
    ExportJsonWebKeyKeyFn<PublicKey> exportPublicJsonWebKey,
    @required GenerateKeyPairFn<PrivateKey, PublicKey> generateKeyPair,
    SignBytesFn<PrivateKey> signBytes,
    SignStreamFn<PrivateKey> signStream,
    VerifyBytesFn<PublicKey> verifyBytes,
    VerifyStreamFn<PublicKey> verifyStream,
    EncryptOrDecryptBytesFn<PublicKey> encryptBytes,
    EncryptOrDecryptStreamFn<PublicKey> encryptStream,
    EncryptOrDecryptBytesFn<PrivateKey> decryptBytes,
    EncryptOrDecryptStreamFn<PrivateKey> decryptStream,
  }) {
    return TestRunner._(
      isSymmetric: false,
      importPrivateRawKey: importPrivateRawKey,
      exportPrivateRawKey: exportPrivateRawKey,
      importPrivatePkcs8Key: importPrivatePkcs8Key,
      exportPrivatePkcs8Key: exportPrivatePkcs8Key,
      importPrivateJsonWebKey: importPrivateJsonWebKey,
      exportPrivateJsonWebKey: exportPrivateJsonWebKey,
      importPublicRawKey: importPublicRawKey,
      exportPublicRawKey: exportPublicRawKey,
      importPublicSpkiKey: importPublicSpkiKey,
      exportPublicSpkiKey: exportPublicSpkiKey,
      importPublicJsonWebKey: importPublicJsonWebKey,
      exportPublicJsonWebKey: exportPublicJsonWebKey,
      generateKeyPair: generateKeyPair,
      signBytes: signBytes,
      signStream: signStream,
      verifyBytes: verifyBytes,
      verifyStream: verifyStream,
      encryptBytes: encryptBytes,
      encryptStream: encryptStream,
      decryptBytes: decryptBytes,
      decryptStream: decryptStream,
    );
  }

  /// Create [TestRunner] for an symmetric primitive.
  ///
  /// This just creates a [TestRunner] where public and private key have the
  /// same type. This may give rise to a few unnecessary test cases as
  /// import/export of public and private key
  static TestRunner<PrivateKey, PrivateKey> symmetric<PrivateKey>({
    ImportKeyFn<PrivateKey> importPrivateRawKey,
    ExportKeyFn<PrivateKey> exportPrivateRawKey,
    ImportKeyFn<PrivateKey> importPrivatePkcs8Key,
    ExportKeyFn<PrivateKey> exportPrivatePkcs8Key,
    ImportJsonWebKeyKeyFn<PrivateKey> importPrivateJsonWebKey,
    ExportJsonWebKeyKeyFn<PrivateKey> exportPrivateJsonWebKey,
    @required GenerateKeyFn<PrivateKey> generateKey,
    SignBytesFn<PrivateKey> signBytes,
    SignStreamFn<PrivateKey> signStream,
    VerifyBytesFn<PrivateKey> verifyBytes,
    VerifyStreamFn<PrivateKey> verifyStream,
    EncryptOrDecryptBytesFn<PrivateKey> encryptBytes,
    EncryptOrDecryptStreamFn<PrivateKey> encryptStream,
    EncryptOrDecryptBytesFn<PrivateKey> decryptBytes,
    EncryptOrDecryptStreamFn<PrivateKey> decryptStream,
  }) {
    return TestRunner._(
      isSymmetric: true,
      importPrivateRawKey: importPrivateRawKey,
      exportPrivateRawKey: exportPrivateRawKey,
      importPrivatePkcs8Key: importPrivatePkcs8Key,
      exportPrivatePkcs8Key: exportPrivatePkcs8Key,
      importPrivateJsonWebKey: importPrivateJsonWebKey,
      exportPrivateJsonWebKey: exportPrivateJsonWebKey,
      generateKeyPair: (params) async {
        final k = await generateKey(params);
        return _KeyPair(privateKey: k, publicKey: k);
      },
      signBytes: signBytes,
      signStream: signStream,
      verifyBytes: verifyBytes,
      verifyStream: verifyStream,
      encryptBytes: encryptBytes,
      encryptStream: encryptStream,
      decryptBytes: decryptBytes,
      decryptStream: decryptStream,
    );
  }

  void _validate() {
    // Required operations
    check(_generateKeyPair != null);

    // Check that we have verify if we have sign
    check((_signBytes != null) == (_verifyBytes != null));
    check((_signStream != null) == (_verifyStream != null));
    // If we can sign streams, we should also be able to sign bytes
    if (_signStream != null) {
      check(_signBytes != null);
    }

    // Check that we have decrypt if we have encrypt
    check((_encryptBytes != null) == (_decryptBytes != null));
    check((_encryptStream != null) == (_decryptStream != null));
    // If we can encrypt streams, we should also be able to encrypt bytes
    if (_encryptStream != null) {
      check(_encryptBytes != null);
    }

    // Must have one priate key import format.
    check(_importPrivateRawKey != null ||
        _importPrivatePkcs8Key != null ||
        _importPrivateJsonWebKey != null);

    if (_isSymmetric) {
      // if symmetric we have no methods for importing public keys
      check(_importPublicRawKey == null);
      check(_importPublicSpkiKey == null);
      check(_importPublicJsonWebKey == null);
    } else {
      // Must have one public key import format.
      check(_importPublicRawKey != null ||
          _importPublicSpkiKey != null ||
          _importPublicJsonWebKey != null);
    }

    // Export-only and import-only formats do not make sense
    check(
      (_importPrivateRawKey != null) == (_exportPrivateRawKey != null),
    );
    check(
      (_importPrivatePkcs8Key != null) == (_exportPrivatePkcs8Key != null),
    );
    check(
      (_importPrivateJsonWebKey != null) == (_exportPrivateJsonWebKey != null),
    );
    check(
      (_importPublicRawKey != null) == (_exportPublicRawKey != null),
    );
    check(
      (_importPublicSpkiKey != null) == (_exportPublicSpkiKey != null),
    );
    check(
      (_importPublicJsonWebKey != null) == (_exportPublicJsonWebKey != null),
    );
  }

  Future<TestCase> generate({
    @required Map<String, dynamic> generateKeyParams,
    @required Map<String, dynamic> importKeyParams,
    Map<String, dynamic> signVerifyParams,
    Map<String, dynamic> encryptDecryptParams,
    String plaintextTemplate = libsum,
    int minPlaintext = 8,
    int maxPlaintext = libsum.length,
  }) async {
    check(minPlaintext <= maxPlaintext);
    check(maxPlaintext < plaintextTemplate.length);
    final ts = DateTime.now().toIso8601String().split('.').first; // drop secs
    final name = 'generated at $ts';

    log('generating key-pair');
    final pair = await _generateKeyPair(generateKeyParams);
    final privateKey = pair.privateKey;
    final publicKey = pair.publicKey;
    check(privateKey != null);
    check(publicKey != null);

    log('picking plaintext');
    final rng = Random.secure();
    final N = rng.nextInt(maxPlaintext - minPlaintext) + minPlaintext;
    final offset = rng.nextInt(plaintextTemplate.length - N);
    final plaintext = utf8.encode(plaintextTemplate.substring(
      offset,
      offset + N,
    ));

    List<int> signature;
    if (_signBytes != null) {
      log('creating signature');
      signature = await _signBytes(
        pair.privateKey,
        plaintext,
        signVerifyParams,
      );
    }

    List<int> ciphertext;
    if (_encryptBytes != null) {
      log('creating ciphertext');
      ciphertext = await _encryptBytes(
        pair.publicKey,
        plaintext,
        encryptDecryptParams,
      );
    }

    T optionalCall<S, T>(T Function(S) fn, S v) => fn != null ? fn(v) : null;
    final c = TestCase(
      name,
      generateKeyParams: null, // omit generateKeyParams
      privateRawKeyData: await optionalCall(_exportPrivateRawKey, privateKey),
      privatePkcs8KeyData:
          await optionalCall(_exportPrivatePkcs8Key, privateKey),
      privateJsonWebKeyData:
          await optionalCall(_exportPrivateJsonWebKey, privateKey),
      publicRawKeyData: await optionalCall(_exportPublicRawKey, publicKey),
      publicSpkiKeyData: await optionalCall(_exportPublicSpkiKey, publicKey),
      publicJsonWebKeyData:
          await optionalCall(_exportPublicJsonWebKey, publicKey),
      plaintext: plaintext,
      signature: signature,
      ciphertext: ciphertext,
      importKeyParams: importKeyParams,
      signVerifyParams: signVerifyParams,
      encryptDecryptParams: encryptDecryptParams,
    );

    // Log the generated test case. This makes it easy to copy/paste the test
    // case into test files.
    log(JsonEncoder.withIndent('  ').convert(c.toJson()));

    return c;
  }

  void runAll(Iterable<Map<dynamic, dynamic>> cases) {
    for (final c in cases) {
      run(TestCase.fromJson(c));
    }
  }

  void run(TestCase c) {
    group('${c.name}:', () => _runTests(this, c));
  }
}

void _runTests<PrivateKey, PublicKey>(
  TestRunner<PrivateKey, PublicKey> r,
  TestCase c,
) {
  // Validate that the test case [c] is compatible with TestRunner [r].
  final validate = () {
    final hasPrivateKey = c.privateRawKeyData != null ||
        c.privatePkcs8KeyData != null ||
        c.privateJsonWebKeyData != null;
    final hasPublicKey = c.publicRawKeyData != null ||
        c.publicSpkiKeyData != null ||
        c.publicJsonWebKeyData != null;

    // Test that we have keys to import or generate some.
    if (r._isSymmetric) {
      check(!hasPublicKey);
      check(
        c.generateKeyParams != null || hasPrivateKey,
        'A key must be generated or imported',
      );
    } else {
      check(
        c.generateKeyParams != null || (hasPrivateKey && hasPublicKey),
        'A key-pair must be generated or imported',
      );
    }

    check(c.plaintext != null);
    check(
      c.generateKeyParams == null ||
          (c.signature == null && c.ciphertext == null),
      'Cannot verify signature/ciphertext for a generated key-pair',
    );
    check(c.importKeyParams != null);
    check((c.signVerifyParams != null) == (r._signBytes != null));
    check((c.encryptDecryptParams != null) == (r._encryptBytes != null));
    if (c.signature != null) {
      check(r._signBytes != null);
    }
    if (c.ciphertext != null) {
      check(r._encryptBytes != null);
    }

    // Check that data matches the methods we have in the runner.
    check(r._importPrivateRawKey != null || c.privateRawKeyData == null);
    check(r._importPrivatePkcs8Key != null || c.privatePkcs8KeyData == null);
    check(
        r._importPrivateJsonWebKey != null || c.privateJsonWebKeyData == null);
    check(r._importPublicRawKey != null || c.publicRawKeyData == null);
    check(r._importPublicSpkiKey != null || c.publicSpkiKeyData == null);
    check(r._importPublicJsonWebKey != null || c.publicJsonWebKeyData == null);
  };
  test('validate test case', validate);

  try {
    validate();
  } catch (_) {
    // Don't register additional tests if the test-case is invalid!
    return;
  }

  //------------------------------ Import or generate key-pair for testing

  // Store publicKey and privateKey for use in later tests.
  // If [_isSymmetric] is true, we still import the public and assign the
  // private key to the public key.
  PublicKey publicKey;
  PrivateKey privateKey;

  if (c.generateKeyParams != null) {
    test('generateKeyPair()', () async {
      final pair = await r._generateKeyPair(c.generateKeyParams);
      check(pair.privateKey != null);
      check(pair.publicKey != null);
      publicKey = pair.publicKey;
      privateKey = pair.privateKey;
    });
  } else {
    test('import key-pair', () async {
      // Get a privateKey
      if (c.privateRawKeyData != null) {
        privateKey = await r._importPrivateRawKey(
          c.privateRawKeyData,
          c.importKeyParams,
        );
        check(privateKey != null);
      } else if (c.privatePkcs8KeyData != null) {
        privateKey = await r._importPrivatePkcs8Key(
          c.privatePkcs8KeyData,
          c.importKeyParams,
        );
        check(privateKey != null);
      } else if (c.privateJsonWebKeyData != null) {
        privateKey = await r._importPrivateJsonWebKey(
          c.privateJsonWebKeyData,
          c.importKeyParams,
        );
        check(privateKey != null);
      } else {
        check(false, 'missing private key for importing');
      }

      // Get a publicKey
      if (r._isSymmetric) {
        // If symmetric algorithm we just use the private key.
        publicKey = privateKey as PublicKey;
      } else if (c.publicRawKeyData != null) {
        publicKey = await r._importPublicRawKey(
          c.publicRawKeyData,
          c.importKeyParams,
        );
        check(publicKey != null);
      } else if (c.publicSpkiKeyData != null) {
        publicKey = await r._importPublicSpkiKey(
          c.publicSpkiKeyData,
          c.importKeyParams,
        );
        check(publicKey != null);
      } else if (c.publicJsonWebKeyData != null) {
        publicKey = await r._importPublicJsonWebKey(
          c.publicJsonWebKeyData,
          c.importKeyParams,
        );
        check(publicKey != null);
      } else {
        check(false, 'missing public key for importing');
      }
    });
  }

  //------------------------------ Create a signature for testing

  // Ensure that we have a signature for use in later test cases
  List<int> signature;

  if (r._signBytes != null) {
    if (c.signature != null) {
      signature = c.signature;
    } else {
      test('create signature', () async {
        signature = await r._signBytes(
          privateKey,
          c.plaintext,
          c.signVerifyParams,
        );
      });
    }

    test('verify signature', () async {
      check(
        await r._verifyBytes(
          publicKey,
          signature,
          c.plaintext,
          c.signVerifyParams,
        ),
        'failed to verify signature',
      );
    });
  }

  //------------------------------ Create a ciphertext for testing
  List<int> ciphertext;

  if (r._encryptBytes != null) {
    if (c.ciphertext != null) {
      ciphertext = c.ciphertext;
    } else {
      test('create ciphertext', () async {
        ciphertext = await r._encryptBytes(
          publicKey,
          c.plaintext,
          c.encryptDecryptParams,
        );
      });
    }

    test('decrypt ciphertext', () async {
      final text = await r._decryptBytes(
        privateKey,
        ciphertext,
        c.encryptDecryptParams,
      );
      check(equalBytes(text, c.plaintext), 'failed to decrypt ciphertext');
    });
  }

  //------------------------------ Utilities for testing

  //// Utility function to verify [sig] using [key].
  Future<void> _checkVerifyBytes(PublicKey key, List<int> sig) async {
    check(
      await r._verifyBytes(key, sig, c.plaintext, c.signVerifyParams),
      'failed to verify signature',
    );
    check(
      !await r._verifyBytes(
        key,
        flipFirstBits(sig),
        c.plaintext,
        c.signVerifyParams,
      ),
      'verified an invalid signature',
    );
    if (c.plaintext.isNotEmpty) {
      check(
        !await r._verifyBytes(
          key,
          sig,
          flipFirstBits(c.plaintext),
          c.signVerifyParams,
        ),
        'verified an invalid message',
      );
    }
  }

  /// Utility function to decrypt [ctext] using [key].
  Future<void> _checkDecryptBytes(PrivateKey key, List<int> ctext) async {
    final text = await r._decryptBytes(key, ctext, c.encryptDecryptParams);
    check(equalBytes(text, c.plaintext), 'failed to decrypt ciphertext');

    if (ctext.isNotEmpty) {
      // If ciphertext is mangled some primitives like AES-GCM must throw
      // others may return garbled plaintext.
      try {
        final invalidText = await r._decryptBytes(
          key,
          flipFirstBits(ctext),
          c.encryptDecryptParams,
        );
        check(
          !equalBytes(invalidText, c.plaintext),
          'decrypted an invalid ciphertext',
        );
      } on OperationError catch (e) {
        check(e.toString() != '', 'expected some explanation');
      }
    }
  }

  /// Check if [signature] is sane.
  Future<void> checkSignature(List<int> signature) async {
    check(signature != null, 'signature is null');
    check(signature.isNotEmpty, 'signature is empty');
    await _checkVerifyBytes(publicKey, signature);
  }

  /// Check if [ciphertext] is sane.
  Future<void> checkCipherText(List<int> ctext) async {
    check(ctext != null, 'ciphtertext is null');
    check(ctext.isNotEmpty, 'ciphtertext is empty');
    await _checkDecryptBytes(privateKey, ctext);
  }

  /// Check if [publicKey] is sane.
  Future<void> checkPublicKey(PublicKey publicKey) async {
    check(publicKey != null, 'publicKey is null');
    if (r._signBytes != null) {
      await _checkVerifyBytes(publicKey, signature);
    }
    if (r._encryptBytes != null) {
      final ctext = await r._encryptBytes(
        publicKey,
        c.plaintext,
        c.encryptDecryptParams,
      );
      await checkCipherText(ctext);
    }
  }

  /// Check if [privateKey] is sane.
  Future<void> checkPrivateKey(PrivateKey privateKey) async {
    check(privateKey != null, 'privateKey is null');
    if (r._signBytes != null) {
      final sig = await r._signBytes(
        privateKey,
        c.plaintext,
        c.signVerifyParams,
      );
      await checkSignature(sig);
    }
    if (r._encryptBytes != null) {
      await _checkDecryptBytes(privateKey, ciphertext);
    }
  }

  //------------------------------ Test import public key

  if (c.publicRawKeyData != null) {
    assert(!r._isSymmetric && r._importPublicRawKey != null);

    test('importPublicRawKey()', () async {
      final key = await r._importPublicRawKey(
        c.publicRawKeyData,
        c.importKeyParams,
      );
      await checkPublicKey(key);
    });
  }

  if (c.publicSpkiKeyData != null) {
    assert(!r._isSymmetric && r._importPublicSpkiKey != null);

    test('importPublicSpkiKey()', () async {
      final key = await r._importPublicSpkiKey(
        c.publicSpkiKeyData,
        c.importKeyParams,
      );
      await checkPublicKey(key);
    });
  }

  if (c.publicJsonWebKeyData != null) {
    assert(!r._isSymmetric && r._importPublicJsonWebKey != null);

    test('importPublicJsonWebKey()', () async {
      final key = await r._importPublicJsonWebKey(
        c.publicJsonWebKeyData,
        c.importKeyParams,
      );
      await checkPublicKey(key);
    });
  }

  //------------------------------ Test import private key

  if (c.privateRawKeyData != null) {
    test('importPrivateRawKey()', () async {
      final key = await r._importPrivateRawKey(
        c.privateRawKeyData,
        c.importKeyParams,
      );
      await checkPrivateKey(key);
    });
  }

  if (c.privatePkcs8KeyData != null) {
    test('importPrivatePkcs8Key()', () async {
      final key = await r._importPrivatePkcs8Key(
        c.privatePkcs8KeyData,
        c.importKeyParams,
      );
      await checkPrivateKey(key);
    });
  }

  if (c.privateJsonWebKeyData != null) {
    test('importPrivateJsonWebKey()', () async {
      final key = await r._importPrivateJsonWebKey(
        c.privateJsonWebKeyData,
        c.importKeyParams,
      );
      await checkPrivateKey(key);
    });
  }

  //------------------------------ Test signing

  if (r._signBytes != null) {
    test('signBytes(plaintext)', () async {
      final sig = await r._signBytes(
        privateKey,
        c.plaintext,
        c.signVerifyParams,
      );
      await checkSignature(sig);
    });
  }

  if (r._signStream != null) {
    test('signStream(plaintext)', () async {
      final sig = await r._signStream(
        privateKey,
        Stream.value(c.plaintext),
        c.signVerifyParams,
      );
      await checkSignature(sig);
    });

    test('signStream(fibChunked(plaintext))', () async {
      final sig = await r._signStream(
        privateKey,
        fibonacciChunkedStream(c.plaintext),
        c.signVerifyParams,
      );
      await checkSignature(sig);
    });
  }

  //------------------------------ Test verification

  if (r._verifyBytes != null) {
    test('verifyBytes(signature, plaintext)', () async {
      check(
        await r._verifyBytes(
          publicKey,
          signature,
          c.plaintext,
          c.signVerifyParams,
        ),
        'failed to verify signature',
      );

      check(
        !await r._verifyBytes(
          publicKey,
          flipFirstBits(signature),
          c.plaintext,
          c.signVerifyParams,
        ),
        'verified an invalid signature',
      );

      if (c.plaintext.isNotEmpty) {
        check(
          !await r._verifyBytes(
            publicKey,
            signature,
            flipFirstBits(c.plaintext),
            c.signVerifyParams,
          ),
          'verified an invalid message',
        );
      }
    });
  }

  if (r._verifyStream != null) {
    test('verifyStream(signature, Stream.value(plaintext))', () async {
      check(
        await r._verifyStream(
          publicKey,
          signature,
          Stream.value(c.plaintext),
          c.signVerifyParams,
        ),
        'failed to verify signature',
      );

      check(
        !await r._verifyStream(
          publicKey,
          flipFirstBits(signature),
          Stream.value(c.plaintext),
          c.signVerifyParams,
        ),
        'verified an invalid signature',
      );

      if (c.plaintext.isNotEmpty) {
        check(
          !await r._verifyStream(
            publicKey,
            signature,
            Stream.value(flipFirstBits(c.plaintext)),
            c.signVerifyParams,
          ),
          'verified an invalid message',
        );
      }
    });

    test('verifyStream(signature, fibChunkedStream(plaintext))', () async {
      check(
        await r._verifyStream(
          publicKey,
          signature,
          fibonacciChunkedStream(c.plaintext),
          c.signVerifyParams,
        ),
        'failed to verify signature',
      );

      check(
        !await r._verifyStream(
          publicKey,
          flipFirstBits(signature),
          fibonacciChunkedStream(c.plaintext),
          c.signVerifyParams,
        ),
        'verified an invalid signature',
      );

      if (c.plaintext.isNotEmpty) {
        check(
          !await r._verifyStream(
            publicKey,
            signature,
            fibonacciChunkedStream(flipFirstBits(c.plaintext)),
            c.signVerifyParams,
          ),
          'verified an invalid message',
        );
      }
    });
  }

  //------------------------------ Test encryption

  if (r._encryptBytes != null) {
    test('encryptBytes(plaintext)', () async {
      final ctext = await r._encryptBytes(
        publicKey,
        c.plaintext,
        c.encryptDecryptParams,
      );
      await checkCipherText(ctext);
    });
  }

  if (r._encryptStream != null) {
    test('encryptStream(plaintext)', () async {
      final ctext = await bufferStream(r._encryptStream(
        publicKey,
        Stream.value(c.plaintext),
        c.encryptDecryptParams,
      ));
      await checkCipherText(ctext);
    });

    test('encryptStream(fibChunked(plaintext))', () async {
      final ctext = await bufferStream(r._encryptStream(
        publicKey,
        fibonacciChunkedStream(c.plaintext),
        c.encryptDecryptParams,
      ));
      await checkCipherText(ctext);
    });
  }

  //------------------------------ Test decryption

  if (r._decryptBytes != null) {
    test('decryptBytes(plaintext)', () async {
      final text = await r._decryptBytes(
        privateKey,
        ciphertext,
        c.encryptDecryptParams,
      );
      check(
        equalBytes(text, c.plaintext),
        'failed to decrypt signature',
      );

      if (ciphertext.isNotEmpty) {
        // If ciphertext is mangled some primitives like AES-GCM must throw
        // others may return garbled plaintext.
        try {
          final text2 = await r._decryptBytes(
            privateKey,
            flipFirstBits(ciphertext),
            c.encryptDecryptParams,
          );
          check(
            !equalBytes(text2, c.plaintext),
            'decrypted an invalid ciphertext correctly',
          );
        } on OperationError catch (e) {
          check(e.toString() != '', 'expected some explanation');
        }
      }
    });
  }

  if (r._decryptStream != null) {
    test('decryptStream(Stream.value(ciphertext))', () async {
      final text = await bufferStream(r._decryptStream(
        privateKey,
        Stream.value(ciphertext),
        c.encryptDecryptParams,
      ));
      check(
        equalBytes(text, c.plaintext),
        'failed to decrypt signature',
      );

      if (ciphertext.isNotEmpty) {
        // If ciphertext is mangled some primitives like AES-GCM must throw
        // others may return garbled plaintext.
        try {
          final text2 = await bufferStream(r._decryptStream(
            privateKey,
            Stream.value(flipFirstBits(ciphertext)),
            c.encryptDecryptParams,
          ));
          check(
            !equalBytes(text2, c.plaintext),
            'decrypted an invalid ciphertext correctly',
          );
        } on OperationError catch (e) {
          check(e.toString() != '', 'expected some explanation');
        }
      }
    });

    test('decryptStream(fibChunkedStream(ciphertext))', () async {
      final text = await bufferStream(r._decryptStream(
        privateKey,
        fibonacciChunkedStream(ciphertext),
        c.encryptDecryptParams,
      ));
      check(
        equalBytes(text, c.plaintext),
        'failed to decrypt signature',
      );

      if (ciphertext.isNotEmpty) {
        // If ciphertext is mangled some primitives like AES-GCM must throw
        // others may return garbled plaintext.
        try {
          final text2 = await bufferStream(r._decryptStream(
            privateKey,
            fibonacciChunkedStream(flipFirstBits(ciphertext)),
            c.encryptDecryptParams,
          ));
          check(
            !equalBytes(text2, c.plaintext),
            'decrypted an invalid ciphertext correctly',
          );
        } on OperationError catch (e) {
          check(e.toString() != '', 'expected some explanation');
        }
      }
    });
  }

  //------------------------------ export/import private key
  if (r._exportPrivateRawKey != null) {
    test('export/import raw private key', () async {
      final keyData = await r._exportPrivateRawKey(privateKey);
      check(keyData != null, 'exported key is null');
      check(keyData.isNotEmpty, 'exported key is empty');

      final key = await r._importPrivateRawKey(keyData, c.importKeyParams);
      await checkPrivateKey(key);
    });
  }

  if (r._exportPrivatePkcs8Key != null) {
    test('export/import pkcs8 private key', () async {
      final keyData = await r._exportPrivatePkcs8Key(privateKey);
      check(keyData != null, 'exported key is null');
      check(keyData.isNotEmpty, 'exported key is empty');

      final key = await r._importPrivatePkcs8Key(keyData, c.importKeyParams);
      await checkPrivateKey(key);
    });
  }

  if (r._exportPrivateJsonWebKey != null) {
    test('export/import jwk private key', () async {
      final jwk = await r._exportPrivateJsonWebKey(privateKey);
      check(jwk != null, 'exported key is null');
      check(jwk.isNotEmpty, 'exported key is empty');

      final key = await r._importPrivateJsonWebKey(jwk, c.importKeyParams);
      await checkPrivateKey(key);
    });
  }

  //------------------------------ export/import public key

  if (r._exportPublicRawKey != null) {
    assert(!r._isSymmetric && r._importPublicRawKey != null);

    test('export/import raw public key', () async {
      final keyData = await r._exportPublicRawKey(publicKey);
      check(keyData != null, 'exported key is null');
      check(keyData.isNotEmpty, 'exported key is empty');

      final key = await r._importPublicRawKey(keyData, c.importKeyParams);
      await checkPublicKey(key);
    });
  }

  if (r._exportPublicSpkiKey != null) {
    assert(!r._isSymmetric && r._importPublicSpkiKey != null);

    test('export/import pkcs8 public key', () async {
      final keyData = await r._exportPublicSpkiKey(publicKey);
      check(keyData != null, 'exported key is null');
      check(keyData.isNotEmpty, 'exported key is empty');

      final key = await r._importPublicSpkiKey(keyData, c.importKeyParams);
      await checkPublicKey(key);
    });
  }

  if (r._exportPublicJsonWebKey != null) {
    assert(!r._isSymmetric && r._importPublicJsonWebKey != null);

    test('export/import jwk public key', () async {
      final jwk = await r._exportPublicJsonWebKey(publicKey);
      check(jwk != null, 'exported key is null');
      check(jwk.isNotEmpty, 'exported key is empty');

      final key = await r._importPublicJsonWebKey(jwk, c.importKeyParams);
      await checkPublicKey(key);
    });
  }
}
