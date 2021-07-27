package app

import (
	"os"
)

// BlueprintNamespace defines a namespace where blueprints and associated resources will be allocated
const DefaultBlueprintNamespace = "m4d-blueprints"

func getBlueprintNamespace() string {
	var blueprintNamespaceEnvVar = "BLUEPRINT_NAMESPACE"

	blueprintNamespace := os.Getenv(blueprintNamespaceEnvVar)
	if len(blueprintNamespace) <= 0 {
		blueprintNamespace = DefaultBlueprintNamespace
	}
	return blueprintNamespace
}
