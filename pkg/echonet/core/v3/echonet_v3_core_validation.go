package corev3

import (
	"errors"
	"fmt"
	"regexp"
	"time"
	// "unicode/utf8" // For string length checks if needed
)

// Constants for validation (example lengths, patterns)
const (
	// Assuming DIDs have a common prefix and structure, e.g., "did:echonet:" followed by alphanumeric
	didPattern       = `^did:echonet:[a-zA-Z0-9_.-]+$` // Simplified pattern
	hashHexMinLength = 64 // SHA256 hex string length
	hashHexMaxLength = 64
	// For byte hashes, it would be a length check, e.g., 32 bytes for SHA256
	hashByteLength = 32
)

var (
	// Precompile regex for efficiency
	didRegex = regexp.MustCompile(didPattern)
)

// --- Validation Methods ---

// Validate checks the integrity of NexusContentObjectV1.
func (m *NexusContentObjectV1) Validate() error {
	if m == nil {
		return errors.New("NexusContentObjectV1 is nil")
	}

	// Validate content_id (assuming it's a required, non-empty string, e.g., UUID)
	if m.GetContentId() == "" {
		return errors.New("content_id is required and cannot be empty")
	}
	// Potential UUID check: if !isValidUUID(m.GetContentId()) { return errors.New("content_id is not a valid UUID") }

	// Validate content_hash (required, specific byte length for SHA256)
	if len(m.GetContentHash()) != hashByteLength {
		return fmt.Errorf("content_hash must be %d bytes, got %d", hashByteLength, len(m.GetContentHash()))
	}

	// Validate timestamp_created_ms (must be positive, not excessively in future)
	if m.GetTimestampCreatedMs() <= 0 {
		return errors.New("timestamp_created_ms must be positive")
	}
	// Example future check: 1 hour into the future allowance
	if m.GetTimestampCreatedMs() > (time.Now().UnixMilli() + (60 * 60 * 1000)) {
		return errors.New("timestamp_created_ms cannot be excessively in the future")
	}

	// Validate author_did (required, specific format)
	if m.GetAuthorDid() == "" {
		return errors.New("author_did is required")
	}
	if !didRegex.MatchString(m.GetAuthorDid()) {
		return fmt.Errorf("author_did '%s' does not match expected DID pattern '%s'", m.GetAuthorDid(), didPattern)
	}

	// Validate content_type (required, non-empty)
	if m.GetContentType() == "" {
		return errors.New("content_type is required")
	}
	// Potentially validate against a list of known MIME types or platform types.

	// Validate metadata_json_str (if present, should be valid JSON - conceptual, actual parsing is complex here)
	if m.MetadataJsonStr != nil && m.GetMetadataJsonStr() == "" { // Check if optional field is set but empty
		return errors.New("metadata_json_str, if explicitly set, cannot be an empty string; omit field or provide valid JSON")
	}
	// In a real scenario, you might try to unmarshal it to check validity:
	// var js json.RawMessage
	// if m.MetadataJsonStr != nil && len(m.GetMetadataJsonStr()) > 0 { // Check if it has content
	//    if err := json.Unmarshal([]byte(m.GetMetadataJsonStr()), &js); err != nil {
	//       return fmt.Errorf("metadata_json_str is not valid JSON: %w", err)
	//    }
	// }

	// Validate last_modified_ms (if not 0, must be >= timestamp_created_ms)
	if m.GetLastModifiedMs() != 0 && m.GetLastModifiedMs() < m.GetTimestampCreatedMs() {
		return errors.New("last_modified_ms cannot be earlier than timestamp_created_ms")
	}

	// Validate parent_content_id (if present, should not be empty string, could check format if it's like content_id)
	if m.GetParentContentId() != "" {
		// if !isValidUUID(m.GetParentContentId()) { return errors.New("parent_content_id is not a valid UUID if present") }
		if m.GetParentContentId() == m.GetContentId() {
			return errors.New("parent_content_id cannot be the same as content_id")
		}
	}

	return nil
}

// Validate checks the integrity of NexusUserObjectV1.
func (m *NexusUserObjectV1) Validate() error {
	if m == nil {
		return errors.New("NexusUserObjectV1 is nil")
	}

	// Validate user_did (required, specific format)
	if m.GetUserDid() == "" {
		return errors.New("user_did is required")
	}
	if !didRegex.MatchString(m.GetUserDid()) {
		return fmt.Errorf("user_did '%s' does not match expected DID pattern '%s'", m.GetUserDid(), didPattern)
	}

	// Validate profile_data_hash (required, specific byte length)
	if len(m.GetProfileDataHash()) != hashByteLength {
		return fmt.Errorf("profile_data_hash must be %d bytes, got %d", hashByteLength, len(m.GetProfileDataHash()))
	}

	// Validate reputation_score_int64 (no specific range here, but could be added e.g. non-negative)
	// if m.GetReputationScoreInt64() < 0 { return errors.New("reputation_score_int64 cannot be negative") }

	// Validate pop_state_summary_hash (required, specific byte length)
	if len(m.GetPopStateSummaryHash()) != hashByteLength {
		return fmt.Errorf("pop_state_summary_hash must be %d bytes, got %d", hashByteLength, len(m.GetPopStateSummaryHash()))
	}

	// Validate registration_timestamp_ms (must be positive)
	if m.GetRegistrationTimestampMs() <= 0 {
		return errors.New("registration_timestamp_ms must be positive")
	}

	// Validate last_active_timestamp_ms (if not 0, must be >= registration_timestamp_ms)
	if m.GetLastActiveTimestampMs() != 0 && m.GetLastActiveTimestampMs() < m.GetRegistrationTimestampMs() {
		return errors.New("last_active_timestamp_ms cannot be earlier than registration_timestamp_ms")
	}

	// Validate public_key_pem (if present, should not be empty string, could add PEM format check)
	if m.PublicKeyPem != nil && m.GetPublicKeyPem() == "" { // Check if optional field is set but empty
		return errors.New("public_key_pem, if explicitly set, cannot be an empty string")
	}
	// A real PEM validation is more complex.

	// is_active is boolean, inherently valid type-wise.

	return nil
}

// Validate checks the integrity of NexusInteractionRecordV1.
func (m *NexusInteractionRecordV1) Validate() error {
	if m == nil {
		return errors.New("NexusInteractionRecordV1 is nil")
	}

	if m.GetInteractionId() == "" {
		return errors.New("interaction_id is required")
	}
	// if !isValidUUID(m.GetInteractionId()) { return errors.New("interaction_id is not a valid UUID") }


	if m.GetInteractionType() == InteractionType_INTERACTION_TYPE_UNSPECIFIED {
		return errors.New("interaction_type must be specified")
	}
	// Could check if value is defined in the enum map if more robust check needed.
	// if _, ok := InteractionType_name[int32(m.GetInteractionType())]; !ok {
	//    return fmt.Errorf("interaction_type '%d' is not a valid InteractionType enum value", m.GetInteractionType())
	// }


	if m.GetTimestampMs() <= 0 {
		return errors.New("timestamp_ms must be positive")
	}
	// Example future check
	if m.GetTimestampMs() > (time.Now().UnixMilli() + (60 * 60 * 1000)) {
		return errors.New("timestamp_ms cannot be excessively in the future")
	}

	if m.GetActorDid() == "" {
		return errors.New("actor_did is required")
	}
	if !didRegex.MatchString(m.GetActorDid()) {
		return fmt.Errorf("actor_did '%s' does not match expected DID pattern '%s'", m.GetActorDid(), didPattern)
	}

	// subject_content_id is optional, but if present, validate format (e.g. not empty string)
	if m.SubjectContentId != nil && m.GetSubjectContentId() == "" {
		return errors.New("subject_content_id, if present, cannot be an empty string")
	}
	// target_user_did is optional, but if present, validate format
	if m.TargetUserDid != nil {
		if m.GetTargetUserDid() == "" {
			return errors.New("target_user_did, if present, cannot be an empty string")
		}
		if !didRegex.MatchString(m.GetTargetUserDid()) {
			return fmt.Errorf("target_user_did '%s' does not match expected DID pattern", m.GetTargetUserDid())
		}
		// Example consistency: cannot follow or react to oneself in some contexts
		// if m.GetTargetUserDid() == m.GetActorDid() &&
		//    (m.GetInteractionType() == InteractionType_INTERACTION_TYPE_FOLLOW ||
		//     m.GetInteractionType() == InteractionType_INTERACTION_TYPE_REACTION && m.GetActorDid() != "system_user_for_content_rewards") {
		// 	return errors.New("actor_did and target_user_did cannot be the same for this interaction type")
		// }
	}

	// interaction_metadata_json_str is optional, if present, could check for valid JSON
	if m.InteractionMetadataJsonStr != nil && m.GetInteractionMetadataJsonStr() == "" {
		return errors.New("interaction_metadata_json_str, if explicitly set, cannot be an empty string")
	}

	// interaction_data_hash (required, specific byte length)
	if len(m.GetInteractionDataHash()) != hashByteLength {
		return fmt.Errorf("interaction_data_hash must be %d bytes, got %d", hashByteLength, len(m.GetInteractionDataHash()))
	}

	return nil
}

// Validate checks the integrity of WitnessProofV1.
func (m *WitnessProofV1) Validate() error {
	if m == nil {
		return errors.New("WitnessProofV1 is nil")
	}

	if m.GetWitnessDid() == "" {
		return errors.New("witness_did is required")
	}
	if !didRegex.MatchString(m.GetWitnessDid()) {
		return fmt.Errorf("witness_did '%s' does not match expected DID pattern", m.GetWitnessDid())
	}

	if len(m.GetAttestedDataHash()) != hashByteLength {
		return fmt.Errorf("attested_data_hash must be %d bytes, got %d", hashByteLength, len(m.GetAttestedDataHash()))
	}

	if m.GetTimestampMs() <= 0 {
		return errors.New("timestamp_ms must be positive")
	}

	// Nonce (int64) - specific validation depends on PoW rules (e.g., range, specific properties)

	// previous_proof_hash (can be empty for a genesis proof, otherwise specific length)
	if len(m.GetPreviousProofHash()) != 0 && len(m.GetPreviousProofHash()) != hashByteLength {
		return fmt.Errorf("previous_proof_hash must be empty or %d bytes, got %d", hashByteLength, len(m.GetPreviousProofHash()))
	}

	// Signature (required, non-empty string - format/length depends on signature scheme)
	if m.GetSignature() == "" {
		return errors.New("signature is required and cannot be empty")
	}
	// A real signature validation (verifying it against content and public key) would occur in a different layer,
    // as this Validate() method doesn't have access to the public key or the full signed payload.

	return nil
}

// Helper function (conceptual - actual UUID validation might use a library)
// func isValidUUID(u string) bool {
// 	// Example using google/uuid package:
// 	// _, err := uuid.Parse(u)
// 	// return err == nil
//  return true // Placeholder
// }
