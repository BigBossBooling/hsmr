// File: pkg/echonet/dds/v1/content/addressing.go
package content

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	// "sort" // Might be needed if manifest fields need sorting before hashing
)

const (
	// DefaultChunkSize defines the standard size for content chunks (e.g., 1MB).
	DefaultChunkSize = 1 * 1024 * 1024 // 1 MiB
	HashSize         = sha256.Size     // 32 bytes for SHA256
)

// ContentChunk represents a single chunk of data.
type ContentChunk struct {
	Index     uint32 `json:"index"`      // Sequence number of the chunk
	Data      []byte `json:"-"`          // The actual chunk data (excluded from manifest JSON if manifest only stores hashes)
	ChunkHash []byte `json:"chunk_hash"` // SHA256 hash of the Data
	Size      int64  `json:"size"`       // Size of the chunk data in bytes
}

// ContentManifest describes a piece of content that has been chunked.
// The overall content_hash (from NexusContentObjectV1) could be the hash of this manifest
// when content is chunked, or the hash of the data itself if not chunked.
type ContentManifest struct {
	OriginalContentHash []byte   `json:"original_content_hash"` // Optional: Hash of the original full content, if calculated before chunking
	ChunkHashes         [][]byte `json:"chunk_hashes"`          // Ordered list of SHA256 hashes of the content chunks
	TotalSize           int64    `json:"total_size"`            // Total size of the original content in bytes
	ChunkSize           int    `json:"chunk_size"`            // The chunk size used for this manifest
	// Potentially: EncryptionMetadata if chunks are encrypted
}

// CalculateDataHash computes the SHA256 hash of a byte slice.
func CalculateDataHash(data []byte) []byte {
	h := sha256.New()
	h.Write(data) // Write never returns an error for sha256.New()
	return h.Sum(nil)
}

// ChunkData divides a byte slice into ContentChunks of a specified chunkSize.
// The last chunk may be smaller than chunkSize.
func ChunkData(data []byte, chunkSize int) ([]ContentChunk, error) {
	if chunkSize <= 0 {
		return nil, errors.New("chunkSize must be positive")
	}

	var chunks []ContentChunk
	totalSize := len(data)
	if totalSize == 0 { // Handle empty data explicitly
		return []ContentChunk{}, nil
	}
	var currentPosition int
	var index uint32

	for currentPosition < totalSize {
		endPosition := currentPosition + chunkSize
		if endPosition > totalSize {
			endPosition = totalSize
		}

		chunkData := data[currentPosition:endPosition]
		chunkHash := CalculateDataHash(chunkData)

		chunks = append(chunks, ContentChunk{
			Index:     index,
			Data:      chunkData, // Data is included here for immediate use/storage by caller
			ChunkHash: chunkHash,
			Size:      int64(len(chunkData)),
		})

		currentPosition = endPosition
		index++
	}
	return chunks, nil
}

// CreateManifest creates a ContentManifest from the original data's hash (optional) and its chunks.
func CreateManifest(originalDataHash []byte, chunks []ContentChunk, totalSize int64, usedChunkSize int) (*ContentManifest, error) {
	if len(chunks) == 0 && totalSize > 0 {
		return nil, errors.New("cannot create manifest with no chunks for non-empty content")
	}
	if totalSize == 0 && len(chunks) > 0 { // Allow totalSize = 0 and len(chunks) = 0 for empty content
	    return nil, errors.New("cannot create manifest with chunks for zero total size")
	}
	if totalSize == 0 && len(chunks) == 0 { // Valid case for empty content
	    // Return an empty manifest or one with zero values
	    return &ContentManifest{
            OriginalContentHash: originalDataHash, // Could be hash of empty data or nil
            ChunkHashes:         [][]byte{},
            TotalSize:           0,
            ChunkSize:           usedChunkSize, // Store the intended chunk size even if no chunks
        }, nil
	}


	chunkHashes := make([][]byte, len(chunks))
	var calculatedTotalSizeFromChunks int64
	for i, chunk := range chunks {
		if chunk.Index != uint32(i) {
			return nil, fmt.Errorf("chunk index mismatch: expected %d, got %d", i, chunk.Index)
		}
		// Verify chunk hash if data is present (it should be after ChunkData)
		if len(chunk.Data) > 0 {
		    recalculatedHash := CalculateDataHash(chunk.Data)
		    if !bytes.Equal(recalculatedHash, chunk.ChunkHash) {
		        return nil, fmt.Errorf("chunk %d data hash mismatch during manifest creation", i)
		    }
		} else if len(chunk.ChunkHash) != HashSize { // If no data (e.g. manifest received from remote), hash must be valid length
		    return nil, fmt.Errorf("chunk %d has no data and invalid hash length", i)
		}


		chunkHashes[i] = chunk.ChunkHash
		calculatedTotalSizeFromChunks += chunk.Size
	}

	if totalSize != calculatedTotalSizeFromChunks {
		return nil, fmt.Errorf("totalSize mismatch: manifest totalSize %d, sum of chunk sizes %d", totalSize, calculatedTotalSizeFromChunks)
	}

	return &ContentManifest{
		OriginalContentHash: originalDataHash, // Can be nil if not pre-calculated
		ChunkHashes:         chunkHashes,
		TotalSize:           totalSize,
		ChunkSize:           usedChunkSize,
	}, nil
}

// CalculateManifestHash computes a SHA256 hash of a canonical representation of the ContentManifest.
// The canonical form is important for consistent hashing. JSON is used here.
func CalculateManifestHash(manifest *ContentManifest) ([]byte, error) {
	if manifest == nil {
		return nil, errors.New("manifest cannot be nil")
	}
	// For canonical JSON, ensure fields are always in the same order if using map, or use struct which has defined order.
	// json.Marshal on a struct typically produces fields in order of definition.
	// Sorting slices within the manifest (like ChunkHashes) is NOT done here as their order is critical.
	manifestBytes, err := json.Marshal(manifest)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal manifest to JSON: %w", err)
	}
	return CalculateDataHash(manifestBytes), nil
}

// ReassembleData reconstructs original data from its chunks.
// Chunks must be provided in the correct order.
func ReassembleData(chunks []ContentChunk) ([]byte, error) {
    if len(chunks) == 0 {
        return []byte{}, nil // Empty chunks list results in empty data
    }

    var totalSize int64
    for i, chunk := range chunks {
        if chunk.Index != uint32(i) {
            return nil, fmt.Errorf("chunk index mismatch during reassembly: expected %d, got %d at slice index %d", i, chunk.Index, i)
        }
        if len(chunk.Data) == 0 { // Data must be present in chunks for reassembly
            return nil, fmt.Errorf("chunk %d data is empty during reassembly", chunk.Index)
        }
        // Optional: Verify each chunk's hash against its data again here if paranoid
        // if !bytes.Equal(CalculateDataHash(chunk.Data), chunk.ChunkHash) {
        //    return nil, fmt.Errorf("hash mismatch for chunk %d during reassembly", chunk.Index)
        // }
        totalSize += chunk.Size
    }

    fullData := make([]byte, 0, totalSize) // Pre-allocate slice capacity
    for _, chunk := range chunks {
        fullData = append(fullData, chunk.Data...)
    }
    return fullData, nil
}
