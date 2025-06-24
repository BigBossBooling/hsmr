module github.com/digisocial/nexus-protocol

go 1.20 // Or a version available in the sandbox, assuming 1.18+ for generics

require (
	github.com/google/uuid v1.3.0
	github.com/stretchr/testify v1.8.4
)

// Possible indirect dependencies that testify might pull.
// Leaving them out for now to keep it simple. If `go mod tidy` could run, it would add them.
// require (
// 	github.com/davecgh/go-spew v1.1.1 // indirect
// 	github.com/pmezard/go-difflib v1.0.0 // indirect
// 	gopkg.in/yaml.v3 v3.0.1 // indirect
// )
