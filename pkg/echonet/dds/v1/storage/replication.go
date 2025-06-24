// File: pkg/echonet/dds/v1/storage/replication.go
package storage

import (
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"sort"
	// "hash/crc32" // For consistent hashing if using that approach

	// Adjust import path based on your Go module structure.
	// If your go.mod defines module "github.com/your_org/digisocialblock", then this is correct.
	"github.com/your_org/digisocialblock/pkg/echonet/dds/v1/discovery"
)

// ReplicationManager handles selecting replica nodes and orchestrating replication.
type ReplicationManager struct {
	nodeRegistry discovery.NodeRegistry // To get list of available nodes
	selfNodeDID  string                 // DID of the current node, to exclude itself from replicas if needed
}

// NewReplicationManager creates a new ReplicationManager.
func NewReplicationManager(registry discovery.NodeRegistry, selfDID string) *ReplicationManager {
	if registry == nil {
		// Return a manager that can't do much, or an error, or panic.
		// For now, let it be created, but operations requiring registry will fail.
		fmt.Println("WARNING: NewReplicationManager created with a nil NodeRegistry.")
	}
	return &ReplicationManager{
		nodeRegistry: registry,
		selfNodeDID:  selfDID,
	}
}

// SelectReplicaNodes selects a list of nodes to store replicas of a chunk.
// This is a simplified selection strategy for MVP: sort nodes by DID (for determinism)
// and pick based on a hash of the chunkKey to distribute.
// Excludes selfNodeDID from the list of potential targets.
func (rm *ReplicationManager) SelectReplicaNodes(chunkKeyHex string, availableNodes []discovery.DDSNodeInfo, replicationFactor int) ([]discovery.DDSNodeInfo, error) {
	if replicationFactor <= 0 {
		return nil, errors.New("replicationFactor must be positive")
	}
	if len(chunkKeyHex) == 0 {
	    return nil, errors.New("chunkKeyHex cannot be empty for node selection")
	}

	potentialTargets := make([]discovery.DDSNodeInfo, 0, len(availableNodes))
	for _, node := range availableNodes {
		if node.NodeDID != rm.selfNodeDID { // Exclude self
			potentialTargets = append(potentialTargets, node)
		}
	}

	if len(potentialTargets) == 0 {
		return nil, errors.New("no other available nodes for replication (after excluding self)")
	}

	// If not enough unique nodes (excluding self) to meet replication factor,
    // return all available unique other nodes.
	if len(potentialTargets) < replicationFactor {
		fmt.Printf("WARNING: Not enough unique other nodes (%d) to meet replication factor (%d) for chunk %s. Using all available other nodes.\n",
		    len(potentialTargets), replicationFactor, chunkKeyHex[:min(10, len(chunkKeyHex))])
		return potentialTargets, nil
	}

	// Sort potential targets by NodeDID for deterministic selection order
	sort.Slice(potentialTargets, func(i, j int) bool {
		return potentialTargets[i].NodeDID < potentialTargets[j].NodeDID
	})

	// Simple deterministic selection based on chunkKeyHex hash
	// This is a basic approach. Consistent hashing rings are more robust for node changes.
	h := sha256.Sum256([]byte(chunkKeyHex))
	// Use first 8 bytes of hash to derive a start index.
	// Ensure a broad distribution even if len(potentialTargets) is small.
	startIndex := binary.BigEndian.Uint64(h[:8]) % uint64(len(potentialTargets))

	selectedReplicas := make([]discovery.DDSNodeInfo, 0, replicationFactor)
	for i := 0; i < len(potentialTargets) && len(selectedReplicas) < replicationFactor; i++ {
		currentIndex := (startIndex + uint64(i)) % uint64(len(potentialTargets)) // Iterate circularly from startIndex
		selectedReplicas = append(selectedReplicas, potentialTargets[currentIndex])
	}

	return selectedReplicas, nil
}


// RequestNodeToStoreReplica simulates asking another node to store a chunk.
// In a real system, this would involve P2P network calls (e.g., gRPC, libp2p).
func (rm *ReplicationManager) RequestNodeToStoreReplica(targetNode discovery.DDSNodeInfo, chunkKeyHex string, chunkData []byte) error {
	// This is a stub for P2P communication.
	fmt.Printf("SIMULATE P2P: Requesting node %s (%v) to store chunk %s (size %d bytes).\n",
		targetNode.NodeDID, targetNode.NetworkAddresses, chunkKeyHex[:min(10, len(chunkKeyHex))]+"...", len(chunkData))

	// Simulate outcomes for testing
	if targetNode.NodeDID == "did:echonet:node_always_fails_replication" {
		return fmt.Errorf("simulated P2P storage request failed for node %s", targetNode.NodeDID)
	}
	if len(chunkData) > (10 * 1024 * 1024) { // Example: Fail if chunk is too large (conceptual, 10MB)
	    return fmt.Errorf("simulated P2P storage request failed: chunk too large (%d bytes)", len(chunkData))
	}

	fmt.Printf("SIMULATE P2P: Node %s conceptually ACKNOWLEDGED storage of chunk %s.\n", targetNode.NodeDID, chunkKeyHex[:min(10, len(chunkKeyHex))]+"...")
	return nil // Simulate success
}

// ReplicateChunk orchestrates the replication of a single chunk to selected nodes.
func (rm *ReplicationManager) ReplicateChunk(chunkKeyHex string, chunkData []byte, replicationFactor int) (int, error) {
    if rm.nodeRegistry == nil {
        return 0, errors.New("NodeRegistry not available in ReplicationManager (was nil during construction)")
    }
    allNodes, err := rm.nodeRegistry.DiscoverNodes(nil) // Get all available nodes
    if err != nil {
        return 0, fmt.Errorf("failed to discover nodes for replication: %w", err)
    }

    // Filter out self node from allNodes before checking if enough nodes for replication
    otherNodes := make([]discovery.DDSNodeInfo, 0)
    for _, node := range allNodes {
        if node.NodeDID != rm.selfNodeDID {
            otherNodes = append(otherNodes, node)
        }
    }

    if len(otherNodes) == 0 {
        fmt.Printf("INFO: No other nodes discovered. Cannot replicate chunk %s.\n", chunkKeyHex[:min(10, len(chunkKeyHex))])
        return 0, nil // Not an error, but 0 replications done.
    }


    targetNodes, err := rm.SelectReplicaNodes(chunkKeyHex, otherNodes, replicationFactor) // Pass otherNodes
    if err != nil {
        return 0, fmt.Errorf("failed to select replica nodes for chunk %s: %w", chunkKeyHex[:min(10, len(chunkKeyHex))], err)
    }

    if len(targetNodes) == 0 {
        // This might happen if replicationFactor is positive but SelectReplicaNodes had an issue or returned empty for other reasons
        fmt.Printf("INFO: No target nodes selected for replication of chunk %s despite available other nodes. Check selection logic or replication factor.\n", chunkKeyHex[:min(10, len(chunkKeyHex))])
        return 0, nil
    }

    successfulReplications := 0
    for _, node := range targetNodes {
        if err := rm.RequestNodeToStoreReplica(node, chunkKeyHex, chunkData); err == nil {
            successfulReplications++
        } else {
            fmt.Printf("WARNING: Failed to replicate chunk %s to node %s: %v\n", chunkKeyHex[:min(10, len(chunkKeyHex))], node.NodeDID, err)
            // Implement retry logic or add to a failed replication queue here in a real system
        }
    }
    fmt.Printf("Chunk %s: Attempted replication to %d nodes, %d successful.\n", chunkKeyHex[:min(10, len(chunkKeyHex))], len(targetNodes), successfulReplications)
    return successfulReplications, nil
}

// min is a helper function as math.Min is for float64
func min(a, b int) int {
    if a < b {
        return a
    }
    return b
}
