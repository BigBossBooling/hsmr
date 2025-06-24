// File: pkg/echonet/dds/v1/discovery/nodeinfo_test.go
package discovery

import (
	"strings"
	"testing"
	"time"
)

func TestDDSNodeInfo_Validate_Valid(t *testing.T) {
	info := DDSNodeInfo{
		NodeDID:            "did:echonet:node123",
		NetworkAddresses:   []string{"/ip4/127.0.0.1/tcp/8000"},
		StorageCapacityGB:  1000,
		StorageAvailableGB: 500,
		Region:             "us-west-1",
		LastSeenTimestampMs: time.Now().UnixMilli(),
	}
	if err := info.Validate(); err != nil {
		t.Errorf("Validate() failed for valid DDSNodeInfo: %v", err)
	}
}

func TestDDSNodeInfo_Validate_Invalid(t *testing.T) {
	// Helper to create a base valid object for modification in tests
	newBaseValidInfo := func() DDSNodeInfo {
		return DDSNodeInfo{
			NodeDID:            "did:echonet:node123",
			NetworkAddresses:   []string{"/ip4/127.0.0.1/tcp/8000"},
			StorageCapacityGB:  100,
			StorageAvailableGB: 50,
			Region:             "eu-central-1",
			LastSeenTimestampMs: time.Now().UnixMilli(),
		}
	}

	tests := []struct {
		name        string
		modifier    func(*DDSNodeInfo)
		expectedErr string
	}{
		{
			name:        "missing node DID",
			modifier:    func(ni *DDSNodeInfo) { ni.NodeDID = "" },
			expectedErr: "node_did is required",
		},
		{
			name:        "invalid node DID format (too short)",
			modifier:    func(ni *DDSNodeInfo) { ni.NodeDID = "did:short" },
			expectedErr: "invalid format",
		},
		{
			name:        "invalid node DID format (wrong prefix)",
			modifier:    func(ni *DDSNodeInfo) { ni.NodeDID = "did:other:node123" },
			expectedErr: "invalid format",
		},
		{
			name:        "missing network addresses",
			modifier:    func(ni *DDSNodeInfo) { ni.NetworkAddresses = []string{} },
			expectedErr: "network_address is required",
		},
		{
			name:        "empty network address string",
			modifier:    func(ni *DDSNodeInfo) { ni.NetworkAddresses = []string{""} },
			expectedErr: "cannot contain empty strings",
		},
		{
		    name: "negative last_seen_timestamp_ms",
		    modifier: func(ni *DDSNodeInfo) { ni.LastSeenTimestampMs = -1 },
		    expectedErr: "last_seen_timestamp_ms cannot be negative",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			info := newBaseValidInfo() // Start with a valid one
			tc.modifier(&info)
			err := info.Validate()
			if err == nil {
				t.Errorf("Validate() did not return error for %s", tc.name)
			} else if !strings.Contains(err.Error(), tc.expectedErr) {
				t.Errorf("Validate() error message mismatch for %s: got '%v', expected to contain '%s'", tc.name, err, tc.expectedErr)
			}
		})
	}
}

func TestInMemoryNodeRegistry_RegisterAndDiscover(t *testing.T) {
	registry := NewInMemoryNodeRegistry()
	node1Info := DDSNodeInfo{
		NodeDID:            "did:echonet:node1",
		NetworkAddresses:   []string{"addr1"},
		LastSeenTimestampMs: time.Now().UnixMilli(),
	}
	node2Info := DDSNodeInfo{
		NodeDID:            "did:echonet:node2",
		NetworkAddresses:   []string{"addr2"},
		LastSeenTimestampMs: time.Now().UnixMilli(),
	}

	// Test RegisterNode
	if err := registry.RegisterNode(node1Info); err != nil {
		t.Fatalf("RegisterNode(node1) failed: %v", err)
	}
	if err := registry.RegisterNode(node2Info); err != nil {
		t.Fatalf("RegisterNode(node2) failed: %v", err)
	}

	// Test invalid registration
	invalidNodeInfo := DDSNodeInfo{NodeDID: "", NetworkAddresses: []string{"addr3"}, LastSeenTimestampMs: time.Now().UnixMilli()}
	if err := registry.RegisterNode(invalidNodeInfo); err == nil {
		t.Error("RegisterNode() should have failed for invalid node info (empty DID)")
	}

	invalidNodeInfo2 := DDSNodeInfo{NodeDID: "did:echonet:nodeinvalid", NetworkAddresses: []string{}}
	if err := registry.RegisterNode(invalidNodeInfo2); err == nil {
		t.Error("RegisterNode() should have failed for invalid node info (no addresses)")
	}


	// Test DiscoverNodes
	discoveredNodes, err := registry.DiscoverNodes(nil) // nil criteria for now
	if err != nil {
		t.Fatalf("DiscoverNodes() failed: %v", err)
	}
	if len(discoveredNodes) != 2 {
		t.Errorf("DiscoverNodes() expected 2 nodes, got %d", len(discoveredNodes))
	}

    foundNode1 := false
    foundNode2 := false
    for _, n := range discoveredNodes {
        if n.NodeDID == "did:echonet:node1" {
            foundNode1 = true
        }
        if n.NodeDID == "did:echonet:node2" {
            foundNode2 = true
        }
    }
    if !foundNode1 || !foundNode2 {
        t.Error("DiscoverNodes() did not return all registered nodes")
    }

	// Test GetNode
	retrievedNode1, err := registry.GetNode("did:echonet:node1")
	if err != nil {
		t.Fatalf("GetNode('did:echonet:node1') failed: %v", err)
	}
	if retrievedNode1 == nil || retrievedNode1.NodeDID != "did:echonet:node1" {
		t.Errorf("GetNode returned incorrect node or nil for node1")
	}

	retrievedNode2, err := registry.GetNode("did:echonet:node2")
	if err != nil {
		t.Fatalf("GetNode('did:echonet:node2') failed: %v", err)
	}
	if retrievedNode2 == nil || retrievedNode2.NodeDID != "did:echonet:node2" {
		t.Errorf("GetNode returned incorrect node or nil for node2")
	}


	_, err = registry.GetNode("did:echonet:nonexistent")
	if err == nil {
		t.Error("GetNode should have failed for non-existent node")
	} else if !strings.Contains(err.Error(), "not found in registry") {
		t.Errorf("GetNode error message mismatch for non-existent node: got '%v'", err)
	}
}

func TestInMemoryNodeRegistry_DiscoverNodes_Empty(t *testing.T) {
	registry := NewInMemoryNodeRegistry()
	nodes, err := registry.DiscoverNodes(nil)
	if err != nil {
		t.Fatalf("DiscoverNodes() on empty registry failed: %v", err)
	}
	if len(nodes) != 0 {
		t.Errorf("DiscoverNodes() on empty registry expected 0 nodes, got %d", len(nodes))
	}
}

func TestInMemoryNodeRegistry_Register_Update(t *testing.T) {
	registry := NewInMemoryNodeRegistry()
	nodeInfo1 := DDSNodeInfo{
		NodeDID:            "did:echonet:node1",
		NetworkAddresses:   []string{"addr1_v1"},
		Region:             "region_v1",
		LastSeenTimestampMs: time.Now().UnixMilli(),
	}
	if err := registry.RegisterNode(nodeInfo1); err != nil {
		t.Fatalf("Initial RegisterNode failed: %v", err)
	}

	retrievedNode, _ := registry.GetNode("did:echonet:node1")
	if retrievedNode.Region != "region_v1" {
		t.Errorf("Expected region_v1, got %s", retrievedNode.Region)
	}

	nodeInfo2 := DDSNodeInfo{ // Same DID, updated info
		NodeDID:            "did:echonet:node1",
		NetworkAddresses:   []string{"addr1_v2"},
		Region:             "region_v2",
		LastSeenTimestampMs: time.Now().UnixMilli() + 1000,
	}
	if err := registry.RegisterNode(nodeInfo2); err != nil {
		t.Fatalf("Updating RegisterNode failed: %v", err)
	}

	retrievedNodeUpdated, _ := registry.GetNode("did:echonet:node1")
	if retrievedNodeUpdated.Region != "region_v2" {
		t.Errorf("Expected updated region_v2, got %s", retrievedNodeUpdated.Region)
	}
	if len(retrievedNodeUpdated.NetworkAddresses) != 1 || retrievedNodeUpdated.NetworkAddresses[0] != "addr1_v2" {
		t.Errorf("Expected updated network address addr1_v2, got %v", retrievedNodeUpdated.NetworkAddresses)
	}
	if len(registry.nodes) != 1 {
		t.Errorf("Expected 1 node after update, got %d", len(registry.nodes))
	}
}
