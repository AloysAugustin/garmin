// Generates source/tests/TeslaGoVectors.mc: AES-GCM command/response vectors
// checked against Tesla's own Go implementation (github.com/teslamotors/
// vehicle-command), which plays the vehicle.
//
//  1. Builds an encrypted VCSEC unlock command exactly as the watch app does
//     (fixed nonce/uuid so the bytes are reproducible), using only the Go
//     standard library for AES-GCM, and checks that Tesla's vehicle-side
//     authentication.Verifier accepts it and recovers the plaintext.
//  2. Has the Verifier encrypt replies to that command (as the car does when
//     FLAG_ENCRYPT_RESPONSE is set) for the app to decrypt.
//
// The keys are the published test keys from protocol.md. The Verifier picks a
// random epoch, so each run produces different (equally valid) vectors.
//
// Usage (internal packages are only importable from inside the module):
//
//	git clone https://github.com/teslamotors/vehicle-command
//	mkdir vehicle-command/cmd/ciqvectors
//	cp tools/vectors/tesla_gcm_vectors.go vehicle-command/cmd/ciqvectors/main.go
//	(cd vehicle-command && go run ./cmd/ciqvectors) > source/tests/TeslaGoVectors.mc
package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"log"

	"google.golang.org/protobuf/proto"

	"github.com/teslamotors/vehicle-command/internal/authentication"
	"github.com/teslamotors/vehicle-command/pkg/protocol/protobuf/errors"
	"github.com/teslamotors/vehicle-command/pkg/protocol/protobuf/signatures"
	universal "github.com/teslamotors/vehicle-command/pkg/protocol/protobuf/universalmessage"
	"github.com/teslamotors/vehicle-command/pkg/protocol/protobuf/vcsec"
)

const (
	vehiclePriv = "344ee5b466a7cf1eeb12b6f50331db2e5ec5834ef5f4befcfd8cbe55c2528d70"
	clientPub   = "04b2b6bc68c2da0665ce656815594996c62394edd8bea905fe781a754fe6a845a714330902f225e9269d466e05b349981fda9d85cc23c6fb444aa73b629105dc6e"
	sharedK     = "1b2fce19967b79db696f909cff89ea9a"
	vin         = "5YJ30123456789ABC"
	routing     = "2c907bd76c640d360b3027dc7404efde"
	uuid        = "1588d5a30eabc6f8fc9a951b11f6fd11"
	nonce       = "a1b2c3d4e5f60718293a4b5c"
	plaintext   = "1000" // UnsignedMessage { RKEAction = RKE_ACTION_UNLOCK }
	ttl         = 30
)

func unhex(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		log.Fatal(err)
	}
	return b
}

func tlv(m *bytes.Buffer, tag signatures.Tag, v []byte) {
	m.WriteByte(byte(tag))
	m.WriteByte(byte(len(v)))
	m.Write(v)
}

func u32(v uint32) []byte {
	b := make([]byte, 4)
	binary.BigEndian.PutUint32(b, v)
	return b
}

func main() {
	domain := universal.Domain_DOMAIN_VEHICLE_SECURITY
	verifier, err := authentication.NewVerifier(
		authentication.UnmarshalECDHPrivateKey(unhex(vehiclePriv)), []byte(vin), domain, unhex(clientPub))
	if err != nil {
		log.Fatal(err)
	}
	info, err := verifier.SessionInfo()
	if err != nil {
		log.Fatal(err)
	}
	counter := info.Counter + 1
	expiresAt := info.ClockTime + ttl
	flags := uint32(1 << universal.Flags_FLAG_ENCRYPT_RESPONSE)

	// Request metadata M and AES-GCM, written out independently of the
	// library's own (internal) metadata code.
	var m bytes.Buffer
	tlv(&m, signatures.Tag_TAG_SIGNATURE_TYPE, []byte{byte(signatures.SignatureType_SIGNATURE_TYPE_AES_GCM_PERSONALIZED)})
	tlv(&m, signatures.Tag_TAG_DOMAIN, []byte{byte(domain)})
	tlv(&m, signatures.Tag_TAG_PERSONALIZATION, []byte(vin))
	tlv(&m, signatures.Tag_TAG_EPOCH, info.Epoch)
	tlv(&m, signatures.Tag_TAG_EXPIRES_AT, u32(expiresAt))
	tlv(&m, signatures.Tag_TAG_COUNTER, u32(counter))
	tlv(&m, signatures.Tag_TAG_FLAGS, u32(flags))
	m.WriteByte(byte(signatures.Tag_TAG_END))
	aad := sha256.Sum256(m.Bytes())

	block, _ := aes.NewCipher(unhex(sharedK))
	gcm, _ := cipher.NewGCM(block)
	sealed := gcm.Seal(nil, unhex(nonce), unhex(plaintext), aad[:])
	ct, tag := sealed[:len(sealed)-16], sealed[len(sealed)-16:]

	cmd := &universal.RoutableMessage{
		ToDestination: &universal.Destination{
			SubDestination: &universal.Destination_Domain{Domain: domain}},
		FromDestination: &universal.Destination{
			SubDestination: &universal.Destination_RoutingAddress{RoutingAddress: unhex(routing)}},
		Payload: &universal.RoutableMessage_ProtobufMessageAsBytes{ProtobufMessageAsBytes: ct},
		SubSigData: &universal.RoutableMessage_SignatureData{SignatureData: &signatures.SignatureData{
			SignerIdentity: &signatures.KeyIdentity{
				IdentityType: &signatures.KeyIdentity_PublicKey{PublicKey: unhex(clientPub)}},
			SigType: &signatures.SignatureData_AES_GCM_PersonalizedData{
				AES_GCM_PersonalizedData: &signatures.AES_GCM_Personalized_Signature_Data{
					Epoch: info.Epoch, Nonce: unhex(nonce), Counter: counter,
					ExpiresAt: expiresAt, Tag: tag,
				}},
		}},
		Uuid:  unhex(uuid),
		Flags: flags,
	}
	cmdBytes, err := proto.MarshalOptions{Deterministic: true}.Marshal(cmd)
	if err != nil {
		log.Fatal(err)
	}

	// The car's side: Tesla's Verifier must accept the command.
	parsed := &universal.RoutableMessage{}
	if err := proto.Unmarshal(cmdBytes, parsed); err != nil {
		log.Fatal(err)
	}
	got, err := verifier.Verify(parsed)
	if err != nil {
		log.Fatalf("Tesla's verifier rejected the command: %v", err)
	}
	if !bytes.Equal(got, unhex(plaintext)) {
		log.Fatalf("verifier decrypted %x", got)
	}
	requestHash := authentication.RequestID(parsed)

	// Replies, encrypted by the Verifier as the car would.
	reply := func(payload []byte, replyCounter uint32, replyFlags uint32) []byte {
		r := &universal.RoutableMessage{
			ToDestination: &universal.Destination{
				SubDestination: &universal.Destination_RoutingAddress{RoutingAddress: unhex(routing)}},
			FromDestination: &universal.Destination{
				SubDestination: &universal.Destination_Domain{Domain: domain}},
			Payload: &universal.RoutableMessage_ProtobufMessageAsBytes{ProtobufMessageAsBytes: payload},
			Flags:   replyFlags,
		}
		if err := verifier.Encrypt(r, requestHash, replyCounter); err != nil {
			log.Fatal(err)
		}
		b, err := proto.MarshalOptions{Deterministic: true}.Marshal(r)
		if err != nil {
			log.Fatal(err)
		}
		return b
	}
	refused, _ := proto.Marshal(&vcsec.FromVCSECMessage{SubMessage: &vcsec.FromVCSECMessage_NominalError{
		NominalError: &errors.NominalError{GenericError: errors.GenericError_E_GENERICERROR_CLOSURES_OPEN}}})
	replyRefused := reply(refused, 1, 0)
	replyEmpty := reply([]byte{}, 2, 1)

	fmt.Println("// Generated by tools/vectors/tesla_gcm_vectors.go - do not edit.")
	fmt.Println("// AES-GCM command/reply vectors checked against Tesla's vehicle-command")
	fmt.Println("// Verifier (the vehicle side of the protocol), with the published test keys.")
	fmt.Println("(:test)")
	fmt.Println("module TeslaGoVectors {")
	fmt.Printf("    const EPOCH = \"%x\";\n", info.Epoch)
	fmt.Printf("    const COUNTER = %d;\n", counter)
	fmt.Printf("    const EXPIRES_AT = %d;\n", expiresAt)
	fmt.Printf("    const NONCE = \"%s\";\n", nonce)
	fmt.Printf("    const PLAINTEXT = \"%s\";\n", plaintext)
	fmt.Println("    // Encrypted unlock command; Tesla's Verifier accepted it.")
	fmt.Printf("    const COMMAND = \"%x\";\n", cmdBytes)
	fmt.Printf("    const REQUEST_HASH = \"%x\";\n", requestHash)
	fmt.Println("    // Replies encrypted by the Verifier: nominalError CLOSURES_OPEN")
	fmt.Println("    // (counter 1, flags 0) and an empty message (counter 2, flags 1).")
	fmt.Printf("    const REPLY_REFUSED = \"%x\";\n", replyRefused)
	fmt.Printf("    const REPLY_REFUSED_PLAINTEXT = \"%x\";\n", refused)
	fmt.Printf("    const REPLY_EMPTY = \"%x\";\n", replyEmpty)
	fmt.Println("}")
}
