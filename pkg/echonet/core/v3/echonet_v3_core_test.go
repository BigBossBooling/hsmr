package corev3

import (
	"bytes" // For comparing byte slices
	"regexp"
	"strings"
	"testing"
	"time"

	"google.golang.org/protobuf/proto" // For proto.Equal and Marshal/Unmarshal tests
)

// Pre-compiled regex for DID pattern (should match the one in validation file)
var testDidRegex = regexp.MustCompile(`^did:echonet:[a-zA-Z0-9_.-]+$`)
const testHashByteLength = 32


// Helper function to create a valid NexusContentObjectV1 for tests
func newValidNexusContentObjectV1() *NexusContentObjectV1 {
	validTimestamp := time.Now().UnixMilli() - (10 * 60 * 1000) // 10 mins ago
	return &NexusContentObjectV1{
		ContentId:          "content-uuid-123",
		ContentHash:        make([]byte, testHashByteLength), // Placeholder valid hash
		TimestampCreatedMs: validTimestamp,
		AuthorDid:          "did:echonet:user_author_123",
		ContentType:        "text/markdown",
		MetadataJsonStr:    proto.String(`{"key": "value"}`),
		LastModifiedMs:     validTimestamp + (5 * 60 * 1000), // 5 mins after creation
		ParentContentId:    "parent-content-uuid-456",
	}
}

func TestValidateNexusContentObjectV1_ValidCase(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	if err := obj.Validate(); err != nil {
		t.Errorf("Validate() returned error for a valid object: %v", err)
	}
}

func TestValidateNexusContentObjectV1_NilObject(t *testing.T) {
	var obj *NexusContentObjectV1 = nil
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "NexusContentObjectV1 is nil") {
		t.Errorf("Validate() did not return expected error for nil object: %v", err)
	}
}

func TestValidateNexusContentObjectV1_MissingContentId(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.ContentId = ""
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "content_id is required") {
		t.Errorf("Validate() did not return expected error for missing content_id: %v", err)
	}
}

func TestValidateNexusContentObjectV1_InvalidContentHashLength(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.ContentHash = make([]byte, 31) // Incorrect length
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "content_hash must be") {
		t.Errorf("Validate() did not return expected error for invalid content_hash length: %v", err)
	}
}

func TestValidateNexusContentObjectV1_InvalidTimestampCreated(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.TimestampCreatedMs = 0
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "timestamp_created_ms must be positive") {
		t.Errorf("Validate() did not return expected error for zero timestamp_created_ms: %v", err)
	}

	obj.TimestampCreatedMs = -100
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "timestamp_created_ms must be positive") {
		t.Errorf("Validate() did not return expected error for negative timestamp_created_ms: %v", err)
	}
}

func TestValidateNexusContentObjectV1_TimestampInFuture(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.TimestampCreatedMs = time.Now().UnixMilli() + (2 * 60 * 60 * 1000) // 2 hours in future
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "timestamp_created_ms cannot be excessively in the future") {
		t.Errorf("Validate() did not return expected error for future timestamp: %v", err)
	}
}


func TestValidateNexusContentObjectV1_MissingAuthorDid(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.AuthorDid = ""
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "author_did is required") {
		t.Errorf("Validate() did not return expected error for missing author_did: %v", err)
	}
}

func TestValidateNexusContentObjectV1_InvalidAuthorDidFormat(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.AuthorDid = "invalid-did-format"
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "does not match expected DID pattern") {
		t.Errorf("Validate() did not return expected error for invalid author_did format: %v", err)
	}
}

func TestValidateNexusContentObjectV1_MissingContentType(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.ContentType = ""
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "content_type is required") {
		t.Errorf("Validate() did not return expected error for missing content_type: %v", err)
	}
}

func TestValidateNexusContentObjectV1_LastModifiedBeforeCreated(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.LastModifiedMs = obj.TimestampCreatedMs - 1000
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "last_modified_ms cannot be earlier than timestamp_created_ms") {
		t.Errorf("Validate() did not return expected error for last_modified_ms < timestamp_created_ms: %v", err)
	}
}

func TestValidateNexusContentObjectV1_ParentIdSameAsContentId(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.ParentContentId = obj.ContentId
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "parent_content_id cannot be the same as content_id") {
		t.Errorf("Validate() did not return expected error for parent_content_id == content_id: %v", err)
	}
}

func TestValidateNexusContentObjectV1_MetadataJsonStrEmptyIfSet(t *testing.T) {
	obj := newValidNexusContentObjectV1()
	obj.MetadataJsonStr = proto.String("") // Set to empty string
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "metadata_json_str, if explicitly set, cannot be an empty string") {
		t.Errorf("Validate() did not return expected error for metadata_json_str being empty when set: %v", err)
	}
}


func TestNexusContentObjectV1_ProtoMarshalUnmarshal(t *testing.T) {
	original := newValidNexusContentObjectV1()

	data, err := proto.Marshal(original)
	if err != nil {
		t.Fatalf("proto.Marshal failed: %v", err)
	}

	unmarshaled := &NexusContentObjectV1{}
	if err := proto.Unmarshal(data, unmarshaled); err != nil {
		t.Fatalf("proto.Unmarshal failed: %v", err)
	}

	// Compare using proto.Equal for semantic equality of protobuf messages
	if !proto.Equal(original, unmarshaled) {
		t.Errorf("Original and unmarshaled objects are not equal.\nOriginal: %v\nUnmarshaled: %v", original, unmarshaled)
	}

	// Additionally, check a few fields manually if needed, especially byte slices
	if original.ContentId != unmarshaled.ContentId {
		t.Errorf("ContentId mismatch: expected %s, got %s", original.ContentId, unmarshaled.ContentId)
	}
	if !bytes.Equal(original.ContentHash, unmarshaled.ContentHash) {
		t.Errorf("ContentHash mismatch")
	}
}


// --- Tests for NexusUserObjectV1 ---
func newValidNexusUserObjectV1() *NexusUserObjectV1 {
    validTimestamp := time.Now().UnixMilli() - (24 * 60 * 60 * 1000) // 1 day ago
	return &NexusUserObjectV1{
		UserDid:                 "did:echonet:user_valid_789",
		ProfileDataHash:         make([]byte, testHashByteLength),
		ReputationScoreInt64:    1000,
		PopStateSummaryHash:     make([]byte, testHashByteLength),
		RegistrationTimestampMs: validTimestamp,
		LastActiveTimestampMs:   validTimestamp + (12 * 60 * 60 * 1000), // 12 hours after registration
		PublicKeyPem:            proto.String("-----BEGIN PUBLIC KEY-----...-----END PUBLIC KEY-----"),
		IsActive:                true,
	}
}

func TestValidateNexusUserObjectV1_ValidCase(t *testing.T) {
	obj := newValidNexusUserObjectV1()
	if err := obj.Validate(); err != nil {
		t.Errorf("Validate() returned error for a valid NexusUserObjectV1: %v", err)
	}
}

func TestValidateNexusUserObjectV1_InvalidUserDid(t *testing.T) {
	obj := newValidNexusUserObjectV1()
	obj.UserDid = ""
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "user_did is required") {
		t.Errorf("Validate() failed for empty user_did: %v", err)
	}
	obj.UserDid = "invalid"
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "does not match expected DID pattern") {
		t.Errorf("Validate() failed for invalid user_did format: %v", err)
	}
}

func TestValidateNexusUserObjectV1_InvalidProfileDataHash(t *testing.T) {
	obj := newValidNexusUserObjectV1()
	obj.ProfileDataHash = make([]byte, 31)
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "profile_data_hash must be") {
		t.Errorf("Validate() failed for invalid profile_data_hash: %v", err)
	}
}

func TestValidateNexusUserObjectV1_InvalidPopStateSummaryHash(t *testing.T) {
	obj := newValidNexusUserObjectV1()
	obj.PopStateSummaryHash = make([]byte, 10)
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "pop_state_summary_hash must be") {
		t.Errorf("Validate() failed for invalid pop_state_summary_hash: %v", err)
	}
}

func TestValidateNexusUserObjectV1_InvalidRegistrationTimestamp(t *testing.T) {
	obj := newValidNexusUserObjectV1()
	obj.RegistrationTimestampMs = 0
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "registration_timestamp_ms must be positive") {
		t.Errorf("Validate() failed for zero registration_timestamp_ms: %v", err)
	}
}

func TestValidateNexusUserObjectV1_LastActiveBeforeRegistered(t *testing.T) {
	obj := newValidNexusUserObjectV1()
	obj.LastActiveTimestampMs = obj.RegistrationTimestampMs - 1000
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "last_active_timestamp_ms cannot be earlier than registration_timestamp_ms") {
		t.Errorf("Validate() failed for last_active_timestamp_ms < registration_timestamp_ms: %v", err)
	}
}

func TestValidateNexusUserObjectV1_PublicKeyPemEmptyIfSet(t *testing.T) {
	obj := newValidNexusUserObjectV1()
	obj.PublicKeyPem = proto.String("")
	if err := obj.Validate(); err == nil || !strings.Contains(err.Error(), "public_key_pem, if explicitly set, cannot be an empty string") {
		t.Errorf("Validate() failed for empty PublicKeyPem when set: %v", err)
	}
}

func TestNexusUserObjectV1_ProtoMarshalUnmarshal(t *testing.T) {
	original := newValidNexusUserObjectV1()
	data, err := proto.Marshal(original)
	if err != nil { t.Fatalf("Marshal: %v", err) }
	unmarshaled := &NexusUserObjectV1{}
	if err := proto.Unmarshal(data, unmarshaled); err != nil { t.Fatalf("Unmarshal: %v", err) }
	if !proto.Equal(original, unmarshaled) { t.Errorf("Not equal: %v != %v", original, unmarshaled) }
}


// --- Tests for NexusInteractionRecordV1 ---
func newValidNexusInteractionRecordV1() *NexusInteractionRecordV1 {
	return &NexusInteractionRecordV1{
		InteractionId:   "interaction-uuid-789",
		InteractionType: InteractionType_INTERACTION_TYPE_COMMENT,
		TimestampMs:     time.Now().UnixMilli() - (5 * 60 * 1000), // 5 mins ago
		ActorDid:        "did:echonet:user_actor_456",
		SubjectContentId:proto.String("content-uuid-123"),
		TargetUserDid:   proto.String("did:echonet:user_target_789"),
		InteractionMetadataJsonStr: proto.String(`{"comment_length": 50}`),
		InteractionDataHash: make([]byte, testHashByteLength),
	}
}

func TestValidateNexusInteractionRecordV1_ValidCase(t *testing.T) {
	obj := newValidNexusInteractionRecordV1()
	if err := obj.Validate(); err != nil {
		t.Errorf("Validate() returned error for a valid NexusInteractionRecordV1: %v", err)
	}
}
// (Add specific tests for NexusInteractionRecordV1 covering its validation rules)
// - InteractionId required
// - InteractionType unspecified
// - TimestampMs positive and not too far in future
// - ActorDid required and valid format
// - SubjectContentId empty if present (optional field)
// - TargetUserDid empty if present, or valid DID format (optional field)
// - InteractionMetadataJsonStr empty if present
// - InteractionDataHash length

func TestNexusInteractionRecordV1_ProtoMarshalUnmarshal(t *testing.T) {
	original := newValidNexusInteractionRecordV1()
	data, err := proto.Marshal(original)
	if err != nil { t.Fatalf("Marshal: %v", err) }
	unmarshaled := &NexusInteractionRecordV1{}
	if err := proto.Unmarshal(data, unmarshaled); err != nil { t.Fatalf("Unmarshal: %v", err) }
	if !proto.Equal(original, unmarshaled) { t.Errorf("Not equal: %v != %v", original, unmarshaled) }
}


// --- Tests for WitnessProofV1 ---
func newValidWitnessProofV1() *WitnessProofV1 {
	return &WitnessProofV1{
		WitnessDid:        "did:echonet:witness_node_abc",
		AttestedDataHash:  make([]byte, testHashByteLength),
		TimestampMs:       time.Now().UnixMilli() - (1 * 60 * 1000), // 1 min ago
		Nonce:             1234567890,
		PreviousProofHash: make([]byte, testHashByteLength),
		Signature:         "cryptographic_signature_of_witness_node_over_hash_of_fields_1_to_5",
	}
}

func TestValidateWitnessProofV1_ValidCase(t *testing.T) {
	obj := newValidWitnessProofV1()
	if err := obj.Validate(); err != nil {
		t.Errorf("Validate() returned error for a valid WitnessProofV1: %v", err)
	}
}
// (Add specific tests for WitnessProofV1 covering its validation rules)
// - WitnessDid required and valid format
// - AttestedDataHash length
// - TimestampMs positive
// - PreviousProofHash length (if not empty)
// - Signature required

func TestValidateWitnessProofV1_PreviousProofHashEmpty(t *testing.T) {
	obj := newValidWitnessProofV1()
	obj.PreviousProofHash = []byte{} // Empty, valid for genesis
	if err := obj.Validate(); err != nil {
		t.Errorf("Validate() returned error for empty PreviousProofHash: %v", err)
	}
}


func TestWitnessProofV1_ProtoMarshalUnmarshal(t *testing.T) {
	original := newValidWitnessProofV1()
	data, err := proto.Marshal(original)
	if err != nil { t.Fatalf("Marshal: %v", err) }
	unmarshaled := &WitnessProofV1{}
	if err := proto.Unmarshal(data, unmarshaled); err != nil { t.Fatalf("Unmarshal: %v", err) }
	if !proto.Equal(original, unmarshaled) { t.Errorf("Not equal: %v != %v", original, unmarshaled) }
}

// Example of how to use proto.String for optional fields in tests:
// obj.OptionalField = proto.String("some value")
// To test for nil optional field being empty if explicitly set:
// obj.OptionalField = proto.String("")
// err := obj.Validate() -> should catch this if validation logic for "empty if set" exists.

// To test for when an optional field is NOT set (is nil):
// obj.OptionalField = nil // This is the default for pointer types if not set.
// err := obj.Validate() -> should pass if field is truly optional and no "empty if set" rule.

// file_echonet_v3_core_proto_msgTypes is a placeholder for actual generated code.
// In a real generated file, this would be properly defined.
// For testing Validate() methods which don't depend on this internal generated structure,
// the current placeholder Reset() methods are sufficient.
var file_echonet_v3_core_proto_msgTypes = make([]protoimpl.MessageInfo, 4)
func file_echonet_v3_core_proto_init() {} // Placeholder
EOL

echo "Created Go test file: ${TARGET_GO_DIR}/echonet_v3_core_test.go"
ls -l "${TARGET_GO_DIR}/"

# Sanity check: Display first few lines of the generated test file
echo "--- Start of ${TARGET_GO_DIR}/echonet_v3_core_test.go ---"
head -n 20 "${TARGET_GO_DIR}/echonet_v3_core_test.go"
echo "--- End of snippet ---"
