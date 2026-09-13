# Baseline workload hardening for anything shipped through app-delivery. Mirrors
# the posture the golden images already support (nonroot, no privilege
# escalation) so the runtime config doesn't undo the image's guarantees.
package main

import rego.v1

_podspec := input.spec.template.spec if {
	input.spec.template.spec
}

_podspec := input.spec.jobTemplate.spec.template.spec if {
	input.kind == "CronJob"
}

_podspec := input.spec if {
	input.kind == "Pod"
}

_containers contains c if {
	some c in object.get(_podspec, "containers", [])
}

# runAsNonRoot must be true at pod or container level.
deny contains msg if {
	_podspec
	not _podspec.securityContext.runAsNonRoot == true
	some c in _containers
	not c.securityContext.runAsNonRoot == true
	msg := sprintf("%s/%s: must set securityContext.runAsNonRoot: true", [input.kind, c.name])
}

deny contains msg if {
	some c in _containers
	not c.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("%s/%s: must set securityContext.allowPrivilegeEscalation: false", [input.kind, c.name])
}

deny contains msg if {
	some c in _containers
	not c.resources.requests
	msg := sprintf("%s/%s: must set resources.requests", [input.kind, c.name])
}

deny contains msg if {
	some c in _containers
	not c.resources.limits
	msg := sprintf("%s/%s: must set resources.limits", [input.kind, c.name])
}

warn contains msg if {
	some c in _containers
	not c.securityContext.readOnlyRootFilesystem == true
	msg := sprintf("%s/%s: consider readOnlyRootFilesystem: true", [input.kind, c.name])
}
