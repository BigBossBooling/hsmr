// File: pkg/echonet/dds/v1/discovery/nodeinfo.go
package discovery

import (
	"errors"
	"fmt"
	"strings"
	"sync"
	// "time" // Could be added for last_seen timestamps etc.
)

// DDSNodeInfo holds information about a DDS storage node.
type DDSNodeInfo struct {
	NodeDID            string            `json:"node_did"`             // DID of the storage node
	NetworkAddresses   []string          `json:"network_addresses"`    // List of network addresses (e.g., "/ip4/127.0.0.1/tcp/4001/p2p/Qm...")
	StorageCapacityGB  uint64            `json:"storage_capacity_gb"`  // Total storage capacity in GB (conceptual)
	StorageAvailableGB uint64            `json:"storage_available_gb"` // Available storage in GB (conceptual)
	Region             string            `json:"region"`               // Geographic region (conceptual)
	LastSeenTimestampMs int64            `json:"last_seen_timestamp_ms"` // When the node was last seen active
	// Add other relevant metrics like uptime, bandwidth, etc. later
}

// Validate checks basic integrity of DDSNodeInfo.
func (ni *DDSNodeInfo) Validate() error {
	if ni.NodeDID == "" {
		return errors.New("node_did is required")
	}
	// Basic DID format check (can be expanded with regex from corev3 validation if desired)
	if len(ni.NodeDID) < 10 || !strings.HasPrefix(ni.NodeDID, "did:echonet:") {
		return fmt.Errorf("node_did '%s' has invalid format", ni.NodeDID)
	}
	if len(ni.NetworkAddresses) == 0 {
		return errors.New("at least one network_address is required")
	}
	for _, addr := range ni.NetworkAddresses {
		if addr == "" {
			return errors.New("network_addresses cannot contain empty strings")
		}
	}
	// Timestamps could be validated further (e.g., positive)
	if ni.LastSeenTimestampMs < 0 {
	    return errors.New("last_seen_timestamp_ms cannot be negative")
	}
	return nil
}

// NodeRegistry defines an interface for node registration and discovery.
// This would be implemented by on-DLI logic or a dedicated discovery service in production.
type NodeRegistry interface {
	RegisterNode(nodeInfo DDSNodeInfo) error
	DiscoverNodes(filterCriteria map[string]string) ([]DDSNodeInfo, error)
	GetNode(nodeDID string) (*DDSNodeInfo, error)
}

// InMemoryNodeRegistry is a simple in-memory implementation for simulation and testing.
type InMemoryNodeRegistry struct {
	nodes map[string]DDSNodeInfo // Keyed by NodeDID
	mu    sync.RWMutex
}

// NewInMemoryNodeRegistry creates a new in-memory node registry.
func NewInMemoryNodeRegistry() *InMemoryNodeRegistry {
	return &InMemoryNodeRegistry{
		nodes: make(map[string]DDSNodeInfo),
	}
}

// RegisterNode adds or updates a node in the in-memory registry.
func (r *InMemoryNodeRegistry) RegisterNode(nodeInfo DDSNodeInfo) error {
	if err := nodeInfo.Validate(); err != nil {
		return fmt.Errorf("validation failed for node %s: %w", nodeInfo.NodeDID, err)
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.nodes[nodeInfo.NodeDID] = nodeInfo
	fmt.Printf("DEBUG: Node registered/updated in InMemoryRegistry: %s\n", nodeInfo.NodeDID)
	return nil
}

// DiscoverNodes returns a list of nodes from the in-memory registry.
// The filterCriteria is not implemented in this simple version.
func (r *InMemoryNodeRegistry) DiscoverNodes(_ map[string]string) ([]DDSNodeInfo, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	if len(r.nodes) == 0 {
		// Return empty slice and nil error, or specific error if preferred
		return []DDSNodeInfo{}, nil
	}
	nodeList := make([]DDSNodeInfo, 0, len(r.nodes))
	for _, node := range r.nodes {
		nodeList = append(nodeList, node)
	}
	return nodeList, nil
}

// GetNode retrieves a specific node by its DID.
func (r *InMemoryNodeRegistry) GetNode(nodeDID string) (*DDSNodeInfo, error) {
    r.mu.RLock()
    defer r.mu.RUnlock()
    node, exists := r.nodes[nodeDID]
    if !exists {
        return nil, fmt.Errorf("node with DID '%s' not found in registry", nodeDID)
    }
    return &node, nil
}
