// File: pkg/echonet/dds/v1/content/addressing_test.go
package content

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"testing"
	// "google.golang.org/protobuf/proto" // If using proto messages for comparison
)

func TestCalculateDataHash(t *testing.T) {
	data := []byte("hello world")
	hash := CalculateDataHash(data)
	expectedHashHex := "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9" // sha256("hello world")

	hashHex := hex.EncodeToString(hash)
	if hashHex != expectedHashHex {
		t.Errorf("CalculateDataHash() got = %s, want %s", hashHex, expectedHashHex)
	}

	data2 := []byte("hello world!")
	hash2 := CalculateDataHash(data2)
	if bytes.Equal(hash, hash2) {
		t.Error("CalculateDataHash() produced same hash for different data")
	}

	// Test empty data
	emptyHash := CalculateDataHash([]byte{})
	expectedEmptyHashHex := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" // sha256("")
	emptyHashHex := hex.EncodeToString(emptyHash)
	if emptyHashHex != expectedEmptyHashHex {
		t.Errorf("CalculateDataHash() for empty data got = %s, want %s", emptyHashHex, expectedEmptyHashHex)
	}
}

func TestChunkData(t *testing.T) {
	testCases := []struct {
		name        string
		data        []byte
		chunkSize   int
		expectError bool
		expectedNumChunks int
		expectedChunkSizes []int
	}{
		{"empty data", []byte{}, 10, false, 0, []int{}},
		{"small data less than chunk size", []byte("hello"), 10, false, 1, []int{5}},
		{"data equal to chunk size", bytes.Repeat([]byte{0x01}, 10), 10, false, 1, []int{10}},
		{"data larger than chunk size, exact multiple", bytes.Repeat([]byte{0x02}, 20), 10, false, 2, []int{10, 10}},
		{"data larger than chunk size, not exact multiple", bytes.Repeat([]byte{0x03}, 25), 10, false, 3, []int{10, 10, 5}},
		{"zero chunk size", []byte("hello"), 0, true, 0, nil},
		{"negative chunk size", []byte("hello"), -1, true, 0, nil},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			chunks, err := ChunkData(tc.data, tc.chunkSize)
			if tc.expectError {
				if err == nil {
					t.Errorf("ChunkData() expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("ChunkData() returned error: %v", err)
			}
			if len(chunks) != tc.expectedNumChunks {
				t.Errorf("ChunkData() expected %d chunks, got %d", tc.expectedNumChunks, len(chunks))
			}
			// Only check chunk sizes and hashes if chunks were expected
			if tc.expectedNumChunks > 0 && len(chunks) > 0 && tc.expectedChunkSizes != nil {
				for i, chunk := range chunks {
					if chunk.Index != uint32(i) {
						t.Errorf("Chunk %d index mismatch: expected %d, got %d", i, i, chunk.Index)
					}
					if int(chunk.Size) != tc.expectedChunkSizes[i] {
						t.Errorf("Chunk %d size mismatch: expected %d, got %d", i, tc.expectedChunkSizes[i], chunk.Size)
					}
					if !bytes.Equal(CalculateDataHash(chunk.Data), chunk.ChunkHash) {
						t.Errorf("Chunk %d hash mismatch", i)
					}
				}
			}
		})
	}
}


func TestCreateManifestAndHash(t *testing.T) {
	data := bytes.Repeat([]byte{0x0A}, DefaultChunkSize*2+50) // 2 full chunks and one partial
	originalHash := CalculateDataHash(data)
	chunks, _ := ChunkData(data, DefaultChunkSize)

	manifest, err := CreateManifest(originalHash, chunks, int64(len(data)), DefaultChunkSize)
	if err != nil {
		t.Fatalf("CreateManifest() error = %v", err)
	}
	if !bytes.Equal(manifest.OriginalContentHash, originalHash) {
		t.Error("Manifest OriginalContentHash mismatch")
	}
	if len(manifest.ChunkHashes) != len(chunks) {
		t.Errorf("Manifest ChunkHashes count mismatch: expected %d, got %d", len(chunks), len(manifest.ChunkHashes))
	}
	for i, ch := range chunks {
		if !bytes.Equal(manifest.ChunkHashes[i], ch.ChunkHash) {
			t.Errorf("Manifest ChunkHash %d mismatch", i)
		}
	}
	if manifest.TotalSize != int64(len(data)) {
		t.Errorf("Manifest TotalSize mismatch: expected %d, got %d", len(data), manifest.TotalSize)
	}
	if manifest.ChunkSize != DefaultChunkSize {
	    t.Errorf("Manifest ChunkSize mismatch: expected %d, got %d", DefaultChunkSize, manifest.ChunkSize)
	}


	manifestHash, err := CalculateManifestHash(manifest)
	if err != nil {
		t.Fatalf("CalculateManifestHash() error = %v", err)
	}
	if len(manifestHash) != HashSize {
		t.Errorf("CalculateManifestHash() produced hash of incorrect length: %d", len(manifestHash))
	}

	// Test with slightly different manifest to ensure hash changes
	manifest2 := *manifest // shallow copy
	manifest2.TotalSize = manifest.TotalSize + 1
	manifestHash2, _ := CalculateManifestHash(&manifest2)
	if bytes.Equal(manifestHash, manifestHash2) {
		t.Error("CalculateManifestHash() produced same hash for different manifests")
	}

	// Test manifest for empty data
	emptyDataOriginalHash := CalculateDataHash([]byte{})
	emptyChunks, _ := ChunkData([]byte{}, DefaultChunkSize)
	emptyManifest, err := CreateManifest(emptyDataOriginalHash, emptyChunks, 0, DefaultChunkSize)
	if err != nil {
		t.Fatalf("CreateManifest() for empty data error = %v", err)
	}
	if len(emptyManifest.ChunkHashes) != 0 {
		t.Error("Empty manifest should have 0 chunk hashes")
	}
	if emptyManifest.TotalSize != 0 {
		t.Error("Empty manifest TotalSize should be 0")
	}
	if !bytes.Equal(emptyManifest.OriginalContentHash, emptyDataOriginalHash) {
	    t.Error("Empty manifest OriginalContentHash mismatch")
	}
}

func TestCreateManifest_ErrorCases(t *testing.T) {
    // Test case: Mismatched totalSize
    chunks, _ := ChunkData([]byte("test"), DefaultChunkSize)
    _, err := CreateManifest(nil, chunks, 100, DefaultChunkSize) // totalSize 100, but chunk is 4
    if err == nil || !strings.Contains(err.Error(), "totalSize mismatch") {
        t.Errorf("CreateManifest expected totalSize mismatch error, got %v", err)
    }

    // Test case: Chunk index mismatch
    chunk1 := ContentChunk{Index: 0, ChunkHash: CalculateDataHash([]byte("a")), Size:1, Data:[]byte("a")}
    chunk2 := ContentChunk{Index: 2, ChunkHash: CalculateDataHash([]byte("b")), Size:1, Data:[]byte("b")} // Wrong index
    _, err = CreateManifest(nil, []ContentChunk{chunk1, chunk2}, 2, DefaultChunkSize)
    if err == nil || !strings.Contains(err.Error(), "chunk index mismatch") {
        t.Errorf("CreateManifest expected chunk index mismatch error, got %v", err)
    }

    // Test case: Chunk hash mismatch (if data is present in chunk struct)
    chunkWithBadHash := ContentChunk{Index: 0, Data: []byte("data"), ChunkHash: []byte("wronghash"), Size:4}
    _, err = CreateManifest(nil, []ContentChunk{chunkWithBadHash}, 4, DefaultChunkSize)
    if err == nil || !strings.Contains(err.Error(), "chunk 0 data hash mismatch") {
        t.Errorf("CreateManifest expected chunk data hash mismatch, got %v", err)
    }

    // Test case: No chunks for non-empty content
     _, err = CreateManifest(CalculateDataHash([]byte("data")), []ContentChunk{}, 4, DefaultChunkSize)
    if err == nil || !strings.Contains(err.Error(), "cannot create manifest with no chunks for non-empty content") {
        t.Errorf("CreateManifest expected no chunks error, got %v", err)
    }
}


func TestReassembleData(t *testing.T) {
	originalData := make([]byte, DefaultChunkSize*3+123)
	_, err := rand.Read(originalData)
	if err != nil {
		t.Fatalf("Failed to generate random data: %v", err)
	}

	chunks, _ := ChunkData(originalData, DefaultChunkSize)

	// Test 1: Valid reassembly
	reassembledData, err := ReassembleData(chunks)
	if err != nil {
		t.Fatalf("ReassembleData() failed: %v", err)
	}
	if !bytes.Equal(originalData, reassembledData) {
		t.Error("Reassembled data does not match original data")
	}

	// Test 2: Empty chunks list
	emptyReassembled, err := ReassembleData([]ContentChunk{})
	if err != nil {
		t.Fatalf("ReassembleData() with empty chunks failed: %v", err)
	}
	if len(emptyReassembled) != 0 {
		t.Error("ReassembleData() with empty chunks should return empty data")
	}

	// Test 3: Chunk index mismatch
	if len(chunks) > 1 {
		chunksCorrupted := make([]ContentChunk, len(chunks))
		copy(chunksCorrupted, chunks)
		chunksCorrupted[1].Index = 99 // Corrupt index
		_, err = ReassembleData(chunksCorrupted)
		if err == nil || !strings.Contains(err.Error(), "chunk index mismatch during reassembly") {
			t.Errorf("ReassembleData expected index mismatch error, got %v", err)
		}
	}

	// Test 4: Empty chunk data in one of the chunks
	if len(chunks) > 0 {
	    chunksWithEmptyData := make([]ContentChunk, len(chunks))
		copy(chunksWithEmptyData, chunks)
		if len(chunksWithEmptyData) > 0 { // Ensure there's at least one chunk to modify
			chunksWithEmptyData[0].Data = []byte{} // Make first chunk's data empty
			// We might also need to adjust its Size and ChunkHash if those were strictly validated before reassembly
			// but ReassembleData primarily cares about Data field for reassembly.
		}
	     _, err = ReassembleData(chunksWithEmptyData)
		if err == nil || !strings.Contains(err.Error(), "chunk 0 data is empty during reassembly") {
			t.Errorf("ReassembleData expected empty chunk data error, got %v", err)
		}
	}
}

func TestCalculateManifestHash_NilManifest(t *testing.T) {
    _, err := CalculateManifestHash(nil)
    if err == nil || !strings.Contains(err.Error(), "manifest cannot be nil") {
        t.Errorf("CalculateManifestHash expected error for nil manifest, got %v", err)
    }
}
