// File: pkg/echonet/dds/v1/storage/localstore.go
package storage

import (
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	// "github.com/your_org/digisocialblock/pkg/echonet/dds/v1/content" // For content.HashSize
)

const (
	// DefaultBaseDir is the default base directory for local chunk storage.
	DefaultBaseDir = "dds_data"
	// DefaultDirLevels specifies how many levels of subdirectories to create from the hash.
	DefaultDirLevels = 2 // e.g., hash "abcdef..." -> baseDir/ab/cd/abcdef...
	// DefaultDirCharsPerLevel specifies how many characters of the hash to use for each subdir level.
	DefaultDirCharsPerLevel = 2
)

// ChunkStore defines the interface for storing and retrieving content chunks.
type ChunkStore interface {
	Put(chunkKeyHex string, data []byte) error
	Get(chunkKeyHex string) ([]byte, error)
	Delete(chunkKeyHex string) error
	Exists(chunkKeyHex string) (bool, error)
	Location(chunkKeyHex string) string // Returns the conceptual storage location/path
}

// LocalFileChunkStore implements ChunkStore using the local file system.
type LocalFileChunkStore struct {
	baseDir         string
	dirLevels       int
	dirCharsPerLevel int
}

// NewLocalFileChunkStore creates a new LocalFileChunkStore.
// It creates the base directory if it doesn't exist.
func NewLocalFileChunkStore(baseDir string, dirLevels int, dirCharsPerLevel int) (*LocalFileChunkStore, error) {
	if baseDir == "" {
		baseDir = DefaultBaseDir
	}
	if dirLevels <= 0 { // Allow 0 for no subdirectories beyond baseDir
		dirLevels = 0 // DefaultDirLevels
	}
	if dirCharsPerLevel <= 0 && dirLevels > 0 { // Chars per level only relevant if dirLevels > 0
		dirCharsPerLevel = DefaultDirCharsPerLevel
	}


	// Ensure base directory exists
	if err := os.MkdirAll(baseDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create base directory %s: %w", baseDir, err)
	}

	return &LocalFileChunkStore{
		baseDir:         baseDir,
		dirLevels:       dirLevels,
		dirCharsPerLevel: dirCharsPerLevel,
	}, nil
}

// getChunkPath calculates the full path for a chunk based on its hex key.
func (lfs *LocalFileChunkStore) getChunkPath(chunkKeyHex string) (string, error) {
	if lfs.dirLevels > 0 && len(chunkKeyHex) < lfs.dirLevels*lfs.dirCharsPerLevel {
		return "", fmt.Errorf("chunkKeyHex '%s' is too short for configured directory levels (%d) and characters per level (%d)", chunkKeyHex, lfs.dirLevels, lfs.dirCharsPerLevel)
	}

	pathParts := []string{lfs.baseDir}
	for i := 0; i < lfs.dirLevels; i++ {
		start := i * lfs.dirCharsPerLevel
		end := start + lfs.dirCharsPerLevel
		pathParts = append(pathParts, chunkKeyHex[start:end])
	}
	pathParts = append(pathParts, chunkKeyHex)
	return filepath.Join(pathParts...), nil
}

// Put stores a chunk's data. chunkKeyHex is the hex-encoded SHA256 hash of the data.
func (lfs *LocalFileChunkStore) Put(chunkKeyHex string, data []byte) error {
	// Optional: Verify data hash matches chunkKeyHex if desired.
	// This assumes the key is derived from the data by the caller.
	// calculatedDataHash := hex.EncodeToString(content.CalculateDataHash(data))
	// if calculatedDataHash != chunkKeyHex {
	// 	 return fmt.Errorf("data hash mismatch: key is %s, data hashes to %s", chunkKeyHex, calculatedDataHash)
	// }


	filePath, err := lfs.getChunkPath(chunkKeyHex)
	if err != nil {
		return fmt.Errorf("could not determine file path for key %s: %w", chunkKeyHex, err)
	}

	dirPath := filepath.Dir(filePath)
	if err := os.MkdirAll(dirPath, 0755); err != nil {
		return fmt.Errorf("failed to create chunk directory %s: %w", dirPath, err)
	}

	if err := os.WriteFile(filePath, data, 0644); err != nil {
		return fmt.Errorf("failed to write chunk file %s: %w", filePath, err)
	}
	// fmt.Printf("DEBUG: Stored chunk %s at %s\n", chunkKeyHex, filePath)
	return nil
}

// Get retrieves a chunk's data.
func (lfs *LocalFileChunkStore) Get(chunkKeyHex string) ([]byte, error) {
	filePath, err := lfs.getChunkPath(chunkKeyHex)
	if err != nil {
		return nil, fmt.Errorf("could not determine file path for key %s: %w", chunkKeyHex, err)
	}

	data, err := os.ReadFile(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("chunk %s not found at %s: %w", chunkKeyHex, filePath, os.ErrNotExist)
		}
		return nil, fmt.Errorf("failed to read chunk file %s: %w", filePath, err)
	}
	return data, nil
}

// Delete removes a chunk.
func (lfs *LocalFileChunkStore) Delete(chunkKeyHex string) error {
	filePath, err := lfs.getChunkPath(chunkKeyHex)
	if err != nil {
		return fmt.Errorf("could not determine file path for key %s: %w", chunkKeyHex, err)
	}

	err = os.Remove(filePath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("failed to delete chunk file %s: %w", filePath, err)
	}
	// Consider removing empty parent directories, but this is complex and often not required.
	// Example (basic, would need to be more robust):
	// currentDir := filepath.Dir(filePath)
	// for i := 0; i < lfs.dirLevels; i++ {
	//     if empty, _ := isDirEmpty(currentDir); empty {
	//         os.Remove(currentDir)
	//         currentDir = filepath.Dir(currentDir)
	//     } else {
	//         break
	//     }
	// }
	return nil
}

// Exists checks if a chunk exists.
func (lfs *LocalFileChunkStore) Exists(chunkKeyHex string) (bool, error) {
	filePath, err := lfs.getChunkPath(chunkKeyHex)
	if err != nil {
		// If path cannot be determined due to short key, it effectively doesn't exist in a valid state.
		// Return false, nil as it's a predictable "not found due to invalid key for pathing"
		if strings.Contains(err.Error(), "is too short for configured directory levels") {
			return false, nil
		}
		return false, fmt.Errorf("error determining file path for key %s: %w", chunkKeyHex, err)
	}
	_, err = os.Stat(filePath)
	if err == nil {
		return true, nil
	}
	if os.IsNotExist(err) {
		return false, nil
	}
	return false, fmt.Errorf("error checking existence of chunk file %s: %w", filePath, err)
}

// Location returns the conceptual storage path.
func (lfs *LocalFileChunkStore) Location(chunkKeyHex string) string {
    p, err := lfs.getChunkPath(chunkKeyHex)
    if err != nil {
        return fmt.Sprintf("invalid_path_for_key_%s", chunkKeyHex)
    }
    return p
}

// Helper function to check if a directory is empty (conceptual, needs more robust error handling)
// func isDirEmpty(name string) (bool, error) {
//     f, err := os.Open(name)
//     if err != nil {
//         return false, err
//     }
//     defer f.Close()
//     _, err = f.Readdirnames(1) // Or Readdir(1)
//     if err == io.EOF {
//         return true, nil
//     }
//     return false, err // Either not empty or error, excluding io.EOF
// }
