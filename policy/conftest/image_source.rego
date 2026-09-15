# The signature gate: every deployed container image must come from an approved
# golden registry, and must be pinned (no floating :latest / untagged). This is
# what ties app-delivery to golden-image + cgr-sync — you can only ship what the
# golden pipeline produced.
package main

import rego.v1

# --- extract the pod spec for any workload kind ---
podspec := input.spec.template.spec if {
	input.spec.template.spec
}

podspec := input.spec.jobTemplate.spec.template.spec if {
	input.kind == "CronJob"
}

podspec := input.spec if {
	input.kind == "Pod"
}

all_containers contains c if {
	some c in object.get(podspec, "containers", [])
}

all_containers contains c if {
	some c in object.get(podspec, "initContainers", [])
}

allowed(image) if {
	some prefix in data.allowed_registries
	startswith(image, prefix)
}

# Helm test hooks (helm.sh/hook: test) are never applied by Argo CD sync — they
# only run on an explicit `helm test` — so they're out of scope for the
# deployed-image gate. (e.g. Kyverno's readiness-checker test pods.)
is_test_hook if {
	hook := object.get(input.metadata, "annotations", {})
	contains(object.get(hook, "helm.sh/hook", ""), "test")
}

deny contains msg if {
	not is_test_hook
	some c in all_containers
	not allowed(c.image)
	msg := sprintf("%s/%s: image %q is not from an approved golden registry", [input.kind, c.name, c.image])
}

# Pinned: must carry a digest, or a tag that isn't "latest". (Digest preferred.)
deny contains msg if {
	not is_test_hook
	some c in all_containers
	not contains(c.image, "@sha256:")
	endswith(c.image, ":latest")
	msg := sprintf("%s/%s: image %q uses :latest — pin a version or digest", [input.kind, c.name, c.image])
}

deny contains msg if {
	not is_test_hook
	some c in all_containers
	not contains(c.image, "@sha256:")
	not contains(c.image, ":")
	msg := sprintf("%s/%s: image %q has no tag/digest — pin it", [input.kind, c.name, c.image])
}
