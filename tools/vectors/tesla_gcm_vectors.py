#!/usr/bin/env python3
"""Generate source/tests/TeslaGcmVectors.mc: AES-GCM protocol vectors.

* Checks Tesla's own published AES-GCM example (protocol.md, "AES-GCM
  encryption": K, metadata, nonce, ciphertext and tag) with two libraries.
* Builds an encrypted VCSEC unlock command and encrypted replies to it, as
  the vehicle sends them with FLAG_ENCRYPT_RESPONSE, serialized with
  protobuf-python from Tesla's official .proto files and encrypted with
  pyca/cryptography (cross-checked with PyCryptodome). Response metadata
  follows protocol.md "Response metadata" and Peer.responseMetadata in
  vehicle-command/internal/authentication/peer.go.

Usage:
  git clone https://github.com/teslamotors/vehicle-command
  pip install cryptography pycryptodome protobuf grpcio-tools
  python3 -I tools/vectors/tesla_gcm_vectors.py vehicle-command/pkg/protocol/protobuf \\
      > source/tests/TeslaGcmVectors.mc
"""
import hashlib
import importlib
import os
import sys
import tempfile

from Crypto.Cipher import AES
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from grpc_tools import protoc

PROTO_DIR = sys.argv[1]
OUT = tempfile.mkdtemp()
for name in ["universal_message", "signatures", "vcsec", "errors", "keys"]:
    assert protoc.main(["protoc", "-I" + PROTO_DIR, "--python_out=" + OUT,
                        os.path.join(PROTO_DIR, name + ".proto")]) == 0
sys.path.insert(0, OUT)
um = importlib.import_module("universal_message_pb2")
sig = importlib.import_module("signatures_pb2")
vcsec = importlib.import_module("vcsec_pb2")
errors = importlib.import_module("errors_pb2")

K = bytes.fromhex("1b2fce19967b79db696f909cff89ea9a")    # protocol.md shared key
VIN = b"5YJ30123456789ABC"
CLIENT_PUB = bytes.fromhex(
    "04b2b6bc68c2da0665ce656815594996c62394edd8bea905fe781a754fe6a845a7"
    "14330902f225e9269d466e05b349981fda9d85cc23c6fb444aa73b629105dc6e")
EPOCH = bytes.fromhex("4c463f9cc0d3d26906e982ed224adde6")
ROUTING = bytes.fromhex("2c907bd76c640d360b3027dc7404efde")
UUID = bytes.fromhex("1588d5a30eabc6f8fc9a951b11f6fd11")
NONCE = bytes.fromhex("a1b2c3d4e5f60718293a4b5c")
COUNTER, EXPIRES_AT = 8, 2685
VCSEC = um.DOMAIN_VEHICLE_SECURITY
FLAG_ENCRYPT_RESPONSE = 1 << um.FLAG_ENCRYPT_RESPONSE


def seal(key, nonce, pt, aad):
    a = AESGCM(key).encrypt(nonce, pt, aad)
    c = AES.new(key, AES.MODE_GCM, nonce=nonce)
    c.update(aad)
    ct, tag = c.encrypt_and_digest(pt)
    assert a == ct + tag
    return ct, tag


def tlv(tag, value):
    return bytes([tag, len(value)]) + value


def u32(v):
    return v.to_bytes(4, "big")


def request_metadata(domain, counter, expires_at, flags):
    m = tlv(sig.TAG_SIGNATURE_TYPE, bytes([sig.SIGNATURE_TYPE_AES_GCM_PERSONALIZED]))
    m += tlv(sig.TAG_DOMAIN, bytes([domain])) + tlv(sig.TAG_PERSONALIZATION, VIN)
    m += tlv(sig.TAG_EPOCH, EPOCH) + tlv(sig.TAG_EXPIRES_AT, u32(expires_at))
    m += tlv(sig.TAG_COUNTER, u32(counter))
    if flags:
        m += tlv(sig.TAG_FLAGS, u32(flags))
    return m + bytes([sig.TAG_END])


def response_metadata(domain, counter, flags, request_hash, fault):
    m = tlv(sig.TAG_SIGNATURE_TYPE, bytes([sig.SIGNATURE_TYPE_AES_GCM_RESPONSE]))
    m += tlv(sig.TAG_DOMAIN, bytes([domain])) + tlv(sig.TAG_PERSONALIZATION, VIN)
    m += tlv(sig.TAG_COUNTER, u32(counter)) + tlv(sig.TAG_FLAGS, u32(flags))
    m += tlv(sig.TAG_REQUEST_HASH, request_hash) + tlv(sig.TAG_FAULT, u32(fault))
    return m + bytes([sig.TAG_END])


# 1. Tesla's published example (protocol.md): HVAC on, infotainment domain.
doc_meta = request_metadata(um.DOMAIN_INFOTAINMENT, 7, 2655, FLAG_ENCRYPT_RESPONSE)
assert doc_meta.hex() == (
    "000105010103021135594a333031323334353637383941424303104c463f9cc0d3d269"
    "06e982ed224adde6040400000a5f050400000007070400000002ff")
doc_ct, doc_tag = seal(K, bytes.fromhex("dbf79447fa156674dae1caed"), bytes.fromhex("120452020801"),
                       hashlib.sha256(doc_meta).digest())
assert doc_ct.hex() == "38038e8c0f2e" and doc_tag.hex() == "c228e0ff64991481db3a7bbc133696c5"

# 2. Encrypted VCSEC unlock command, as the watch builds it.
plaintext = vcsec.UnsignedMessage(RKEAction=vcsec.RKE_ACTION_UNLOCK).SerializeToString()
meta = request_metadata(VCSEC, COUNTER, EXPIRES_AT, FLAG_ENCRYPT_RESPONSE)
ct, tag = seal(K, NONCE, plaintext, hashlib.sha256(meta).digest())
cmd = um.RoutableMessage()
cmd.to_destination.domain = VCSEC
cmd.from_destination.routing_address = ROUTING
cmd.protobuf_message_as_bytes = ct
cmd.signature_data.signer_identity.public_key = CLIENT_PUB
g = cmd.signature_data.AES_GCM_Personalized_data
g.epoch, g.nonce, g.counter, g.expires_at, g.tag = EPOCH, NONCE, COUNTER, EXPIRES_AT, tag
cmd.uuid = UUID
cmd.flags = FLAG_ENCRYPT_RESPONSE
request_hash = bytes([sig.SIGNATURE_TYPE_AES_GCM_PERSONALIZED]) + tag  # 17 bytes


# 3. Encrypted replies to it.
def reply(payload, counter, flags, nonce, fault=0):
    r = um.RoutableMessage()
    r.to_destination.routing_address = ROUTING
    r.from_destination.domain = VCSEC
    if fault:
        r.signedMessageStatus.operation_status = um.OPERATIONSTATUS_ERROR
        r.signedMessageStatus.signed_message_fault = fault
    aad = hashlib.sha256(response_metadata(VCSEC, counter, flags, request_hash, fault)).digest()
    rct, rtag = seal(K, nonce, payload, aad)
    r.protobuf_message_as_bytes = rct
    d = r.signature_data.AES_GCM_Response_data
    d.nonce, d.counter, d.tag = nonce, counter, rtag
    r.flags = flags
    return r.SerializeToString()


refused = vcsec.FromVCSECMessage()
refused.nominalError.genericError = errors.GENERICERROR_CLOSURES_OPEN
refused = refused.SerializeToString()
r_refused = reply(refused, 1, 0, bytes.fromhex("0102030405060708090a0b0c"))
r_empty = reply(b"", 2, 1, bytes.fromhex("0c0b0a090807060504030201"))
r_fault = reply(b"", 3, 0, bytes.fromhex("00112233445566778899aabb"),
                fault=um.MESSAGEFAULT_ERROR_INVALID_TOKEN_OR_COUNTER)

print("// Generated by tools/vectors/tesla_gcm_vectors.py - do not edit.")
print("// AES-GCM protocol vectors: serialized with protobuf-python from Tesla's")
print("// .proto files, encrypted with pyca/cryptography (checked with PyCryptodome).")
print("(:test)")
print("module TeslaGcmVectors {")
print('    const EPOCH = "%s";' % EPOCH.hex())
print("    const COUNTER = %d;" % COUNTER)
print("    const EXPIRES_AT = %d;" % EXPIRES_AT)
print('    const NONCE = "%s";' % NONCE.hex())
print('    const PLAINTEXT = "%s";' % plaintext.hex())
print("    // Encrypted unlock command (AES_GCM_Personalized_data, flags = 2).")
print('    const COMMAND = "%s";' % cmd.SerializeToString().hex())
print('    const REQUEST_HASH = "%s";' % request_hash.hex())
print("    // Replies: nominalError CLOSURES_OPEN (counter 1, flags 0), an empty")
print("    // message (counter 2, flags 1), and fault INVALID_TOKEN_OR_COUNTER")
print("    // (counter 3) whose fault code is bound into the metadata.")
print('    const REPLY_REFUSED = "%s";' % r_refused.hex())
print('    const REPLY_REFUSED_PLAINTEXT = "%s";' % refused.hex())
print('    const REPLY_EMPTY = "%s";' % r_empty.hex())
print('    const REPLY_FAULT = "%s";' % r_fault.hex())
print("    const REPLY_FAULT_CODE = %d;" % um.MESSAGEFAULT_ERROR_INVALID_TOKEN_OR_COUNTER)
print("}")
