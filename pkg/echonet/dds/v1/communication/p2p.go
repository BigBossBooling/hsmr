// Package communication defines the structures and basic interfaces for peer-to-peer (P2P)
// communication between nodes in the Nexus network. It handles message passing,
// node identity, and basic network event handling.
package communication

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net" // For basic network operations like listening/dialing (can be abstracted later)
	"sync"
	"time"

	"github.com/google/uuid" // For message IDs
	// "github.com/libp2p/go-libp2p" // Example of a more advanced P2P library we might integrate
	// "github.com/libp2p/go-libp2p-core/host"
	// "github.com/libp2p/go-libp2p-core/peer"
)

// NodeID represents a unique identifier for a node.
// This could be a cryptographic public key hash or a randomly generated ID.
type NodeID string

// GenerateNodeID creates a new, unique NodeID (simplified version).
func GenerateNodeID() (NodeID, error) {
	bytes := make([]byte, 16) // 128 bits
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("failed to generate random bytes for NodeID: %w", err)
	}
	return NodeID(hex.EncodeToString(bytes)), nil
}

// MessageType defines the type of a message.
type MessageType uint8

const (
	// MessageType_CUSTOM is for application-specific messages.
	MessageType_CUSTOM MessageType = iota
	// MessageType_HANDSHAKE_INIT initiates a connection.
	MessageType_HANDSHAKE_INIT
	// MessageType_HANDSHAKE_ACK acknowledges a handshake.
	MessageType_HANDSHAKE_ACK
	// MessageType_HEARTBEAT checks if a peer is alive.
	MessageType_HEARTBEAT
	// MessageType_DISCOVERY_QUERY requests peer information.
	MessageType_DISCOVERY_QUERY
	// MessageType_DISCOVERY_RESPONSE provides peer information.
	MessageType_DISCOVERY_RESPONSE
	// MessageType_CHUNK_REQUEST requests a data chunk.
	MessageType_CHUNK_REQUEST
	// MessageType_CHUNK_RESPONSE delivers a data chunk.
	MessageType_CHUNK_RESPONSE
	// MessageType_BROADCAST is for messages intended for multiple peers (semantics depend on transport).
	MessageType_BROADCAST
	// MessageType_ERROR indicates a P2P communication error.
	MessageType_ERROR
)

// String returns a human-readable representation of MessageType.
func (mt MessageType) String() string {
	switch mt {
	case MessageType_CUSTOM:
		return "CUSTOM"
	case MessageType_HANDSHAKE_INIT:
		return "HANDSHAKE_INIT"
	case MessageType_HANDSHAKE_ACK:
		return "HANDSHAKE_ACK"
	case MessageType_HEARTBEAT:
		return "HEARTBEAT"
	case MessageType_DISCOVERY_QUERY:
		return "DISCOVERY_QUERY"
	case MessageType_DISCOVERY_RESPONSE:
		return "DISCOVERY_RESPONSE"
	case MessageType_CHUNK_REQUEST:
		return "CHUNK_REQUEST"
	case MessageType_CHUNK_RESPONSE:
		return "CHUNK_RESPONSE"
	case MessageType_BROADCAST:
		return "BROADCAST"
	case MessageType_ERROR:
		return "ERROR"
	default:
		return fmt.Sprintf("UNKNOWN(%d)", mt)
	}
}

// Message represents a data packet exchanged between nodes.
type Message struct {
	ID        string      // Unique message identifier (e.g., UUID)
	Type      MessageType // Type of the message
	Payload   []byte      // Actual data being sent
	Timestamp int64       // Unix nanoseconds
	SenderID  NodeID      // ID of the sending node
	TargetID  NodeID      // ID of the target node (can be a broadcast ID or empty for some types)
	// Signature []byte    // Cryptographic signature for message authenticity (TODO)
	// HopCount  int       // For routing in larger networks (TODO)
}

// NewMessage creates a new message with a unique ID and current timestamp.
func NewMessage(msgType MessageType, payload []byte, sender NodeID, target NodeID) Message {
	return Message{
		ID:        uuid.NewString(),
		Type:      msgType,
		Payload:   payload,
		Timestamp: time.Now().UnixNano(),
		SenderID:  sender,
		TargetID:  target,
	}
}

// PeerInfo holds information about a known peer.
type PeerInfo struct {
	ID        NodeID
	Address   string    // Network address (e.g., "IP:port")
	LastSeen  time.Time // Timestamp of the last successful contact
	// Add more fields like supported protocols, reputation, etc.
}

// Transport is an interface for the underlying network communication mechanism.
// This allows plugging in different transport layers (TCP, UDP, WebRTC, libp2p).
type Transport interface {
	Listen(ctx context.Context, address string) (net.Listener, error) // Listener for incoming connections
	Dial(ctx context.Context, address string) (net.Conn, error)       // Dial an outgoing connection
	SendMessage(conn net.Conn, msg Message) error
	ReceiveMessage(conn net.Conn) (Message, error)
	Close() error
}

// Node represents a participant in the P2P network.
type Node struct {
	ID          NodeID
	Address     string        // Listening address for this node
	Transport   Transport     // Underlying transport mechanism
	PeerStore   PeerStore     // Manages known peers
	listener    net.Listener  // Active network listener
	stopChan    chan struct{} // Channel to signal shutdown
	handlerLock sync.RWMutex
	handlers    map[MessageType]MessageHandler // Message type specific handlers
	isListening bool
	wg          sync.WaitGroup // To wait for goroutines to finish during shutdown
	mu          sync.Mutex     // Protects isListening and listener fields
}

// MessageHandler is a function type for handling specific message types.
type MessageHandler func(ctx context.Context, msg Message, senderConn net.Conn) error

// PeerStore is an interface for managing and discovering peers.
type PeerStore interface {
	AddPeer(info PeerInfo) error
	GetPeer(id NodeID) (PeerInfo, bool)
	RemovePeer(id NodeID) error
	GetAllPeers() []PeerInfo
	// UpdatePeerLiveness(id NodeID) // Update LastSeen or other liveness metrics
}

// NewNode creates a new P2P node.
// Transport and PeerStore must be provided.
func NewNode(id NodeID, address string, transport Transport, peerStore PeerStore) (*Node, error) {
	if transport == null {
		return nil, errors.New("transport cannot be nil")
	}
	if peerStore == null {
		return nil, errors.New("peerStore cannot be nil")
	}
	return &Node{
		ID:        id,
		Address:   address,
		Transport: transport,
		PeerStore: peerStore,
		stopChan:  make(chan struct{}),
		handlers:  make(map[MessageType]MessageHandler),
	}, nil
}

// RegisterHandler associates a handler function with a message type.
func (n *Node) RegisterHandler(msgType MessageType, handler MessageHandler) {
	n.handlerLock.Lock()
	defer n.handlerLock.Unlock()
	n.handlers[msgType] = handler
}

// Listen starts the node's network listener to accept incoming connections.
func (n *Node) Listen(ctx context.Context) error {
	n.mu.Lock()
	if n.isListening {
		n.mu.Unlock()
		return errors.New("node is already listening")
	}

	// Use node's configured transport to listen
	// This is a simplified representation. Real transport might have more complex setup.
	// listener, err := net.Listen("tcp", n.Address) // Example direct TCP listen
	listener, err := n.Transport.Listen(ctx, n.Address)
	if err != nil {
		n.mu.Unlock()
		return fmt.Errorf("failed to start listener on %s: %w", n.Address, err)
	}
	n.listener = listener
	n.isListening = true
	n.mu.Unlock()

	fmt.Printf("Node %s listening on %s\n", n.ID, n.listener.Addr().String())

	n.wg.Add(1)
	go func() {
		defer n.wg.Done()
		for {
			select {
			case <-n.stopChan:
				fmt.Printf("Node %s: stopping listener.\n", n.ID)
				return
			default:
				// Accept new connections
				// Set a deadline for accept to make it non-blocking and check stopChan
				// This is a common pattern for stoppable listeners.
				// For net.Listener, if it's TCP, you can do:
				if tcpListener, ok := n.listener.(*net.TCPListener); ok {
					tcpListener.SetDeadline(time.Now().Add(1 * time.Second))
				}

				conn, err := n.listener.Accept()
				if err != nil {
					if ne, ok := err.(net.Error); ok && ne.Timeout() {
						continue // Timeout, check stopChan again
					}
					// Check if the error is due to listener being closed.
					if errors.Is(err, net.ErrClosed) {
						fmt.Printf("Node %s: Listener closed, accepting connections stopped.\n", n.ID)
						return
					}
					fmt.Printf("Node %s: Failed to accept connection: %v\n", n.ID, err)
					continue
				}

				fmt.Printf("Node %s: Accepted connection from %s\n", n.ID, conn.RemoteAddr().String())
				n.wg.Add(1)
				go n.handleConnection(ctx, conn)
			}
		}
	}()
	return nil
}

// handleConnection reads messages from a connection and dispatches them to handlers.
func (n *Node) handleConnection(ctx context.Context, conn net.Conn) {
	defer n.wg.Done()
	defer conn.Close() // Ensure connection is closed when handler exits

	for {
		select {
		case <-n.stopChan: // Check if node is shutting down
			return
		case <-ctx.Done(): // Check if context was cancelled (e.g. request-specific context)
			return
		default:
			// In a real transport, ReceiveMessage would handle framing, deadlines, etc.
			// For net.Conn, we might need to implement message framing (e.g., length-prefixing)
			// if the Transport doesn't already.
			// For now, assume Transport.ReceiveMessage handles this.
			msg, err := n.Transport.ReceiveMessage(conn)
			if err != nil {
				if errors.Is(err, net.ErrClosed) || err.Error() == "EOF" { // Simple EOF check
					fmt.Printf("Node %s: Connection closed by peer %s\n", n.ID, conn.RemoteAddr())
					return
				}
				// TODO: Differentiate between recoverable and fatal errors.
				fmt.Printf("Node %s: Error receiving message from %s: %v\n", n.ID, conn.RemoteAddr(), err)
				// Potentially send an error message back if protocol allows
				return // Close connection on significant receive error
			}

			// Process the message
			n.handlerLock.RLock()
			handler, exists := n.handlers[msg.Type]
			n.handlerLock.RUnlock()

			if exists {
				if err := handler(ctx, msg, conn); err != nil {
					fmt.Printf("Node %s: Error handling message type %s from %s: %v\n", n.ID, msg.Type, msg.SenderID, err)
					// Optionally send an error response
				}
			} else {
				fmt.Printf("Node %s: No handler registered for message type %s from %s\n", n.ID, msg.Type, msg.SenderID)
				// Optionally send an "unsupported message type" response
			}
		}
	}
}

// SendMessage sends a message to a target peer.
// This requires the PeerStore to resolve NodeID to a network address.
func (n *Node) SendMessage(ctx context.Context, targetID NodeID, msg Message) error {
	n.mu.Lock()
	if !n.isListening {
		n.mu.Unlock()
		return errors.New("node is not listening, cannot send messages")
	}
	n.mu.Unlock()

	peerInfo, found := n.PeerStore.GetPeer(targetID)
	if !found {
		return fmt.Errorf("peer %s not found in peer store", targetID)
	}

	// Dial the peer using the transport
	// This is a simplified representation. Real transport might have connection pooling.
	conn, err := n.Transport.Dial(ctx, peerInfo.Address)
	if err != nil {
		return fmt.Errorf("failed to dial peer %s at %s: %w", targetID, peerInfo.Address, err)
	}
	defer conn.Close() // Close connection after sending, unless connection pooling is used

	msg.SenderID = n.ID // Ensure sender ID is correctly set
	if err := n.Transport.SendMessage(conn, msg); err != nil {
		return fmt.Errorf("failed to send message to %s: %w", targetID, err)
	}
	fmt.Printf("Node %s: Sent message %s to %s (%s)\n", n.ID, msg.ID, targetID, peerInfo.Address)
	return nil
}

// Broadcast sends a message to all known peers.
// Note: True broadcast behavior depends on the underlying transport.
// This implementation iterates through known peers and sends individually.
func (n *Node) Broadcast(ctx context.Context, msg Message) map[NodeID]error {
	n.mu.Lock()
	if !n.isListening {
		n.mu.Unlock()
		// Or return a single error:
		// return map[NodeID]error{NodeID("BROADCAST_ERROR"): errors.New("node is not listening")}
		errs := make(map[NodeID]error)
		errs[NodeID("SELF_ERROR")] = errors.New("node is not listening, cannot broadcast")
		return errs
	}
	n.mu.Unlock()

	peers := n.PeerStore.GetAllPeers()
	if len(peers) == 0 {
		fmt.Printf("Node %s: No peers to broadcast to.\n", n.ID)
		return nil
	}

	// Ensure SenderID is this node
	msg.SenderID = n.ID
	// TargetID might be a special broadcast ID or ignored by SendMessage if iterating
	// msg.TargetID = BroadcastAddress // If such a concept exists

	errorsMap := make(map[NodeID]error)
	var wg sync.WaitGroup
	var errLock sync.Mutex

	for _, peer := range peers {
		if peer.ID == n.ID { // Don't send to self in this loop
			continue
		}
		wg.Add(1)
		go func(p PeerInfo) {
			defer wg.Done()
			// Create a new message copy for each send if TargetID needs to be specific,
			// or if SendMessage modifies the message. For safety, let's assume it might.
			// If SendMessage is guaranteed not to modify, this copy is not strictly needed.
			peerMsg := msg
			peerMsg.TargetID = p.ID // Set specific target for this send

			if err := n.SendMessage(ctx, p.ID, peerMsg); err != nil {
				errLock.Lock()
				errorsMap[p.ID] = err
				errLock.Unlock()
				fmt.Printf("Node %s: Failed to broadcast message %s to peer %s: %v\n", n.ID, msg.ID, p.ID, err)
			}
		}(peer)
	}
	wg.Wait()

	if len(errorsMap) == 0 {
		return nil
	}
	return errorsMap
}

// Shutdown gracefully stops the node's listener and active connections.
func (n *Node) Shutdown(ctx context.Context) error {
	n.mu.Lock()
	if !n.isListening {
		n.mu.Unlock()
		fmt.Printf("Node %s: Already shut down or was never listening.\n", n.ID)
		return nil // Or an error indicating it wasn't running
	}

	fmt.Printf("Node %s: Initiating shutdown...\n", n.ID)
	close(n.stopChan) // Signal all goroutines to stop

	var listenerErr error
	if n.listener != nil {
		listenerErr = n.listener.Close() // Close the network listener
	}
	n.isListening = false
	n.mu.Unlock()


	// Wait for all goroutines (like handleConnection) to finish
	shutdownComplete := make(chan struct{})
	go func() {
		n.wg.Wait()
		close(shutdownComplete)
	}()

	select {
	case <-shutdownComplete:
		fmt.Printf("Node %s: All connection handlers finished.\n", n.ID)
	case <-ctx.Done():
		fmt.Printf("Node %s: Shutdown timed out waiting for connection handlers: %v\n", n.ID, ctx.Err())
		return ctx.Err()
	}

	// Close the transport
	if n.Transport != nil {
		if err := n.Transport.Close(); err != nil {
			fmt.Printf("Node %s: Error closing transport: %v\n", n.ID, err)
			// Decide if this should be part of the main error returned
		}
	}

	fmt.Printf("Node %s: Shutdown complete.\n", n.ID)
	return listenerErr // Return error from closing listener, if any
}

// TODO:
// - Implement a concrete Transport (e.g., TCPTransport, UDPTransport).
// - Implement a concrete PeerStore (e.g., InMemoryPeerStore, PersistentPeerStore).
// - Add message serialization/deserialization to Transport methods (e.g., JSON, gob, protobuf).
// - Implement handshake logic for new connections.
// - Implement heartbeat/keep-alive mechanism.
// - Implement peer discovery mechanisms (e.g., bootstrap nodes, DHT, mDNS).
// - Add security features: encryption (TLS), message signing, node authentication.
// - More robust error handling and reporting.
// - Connection pooling in Transport or Node.SendMessage.
```
