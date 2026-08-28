# Classification-clearance gating pack, mirroring the maritime-intelligence
# clearance-scoped reads and the platform data-classification ladder. The
# subject's clearance claim must dominate the requested resource
# classification. Absent clearance means UNCLASSIFIED only (fail closed).
package blueeconomy.clearance

import rego.v1

default allow := false

default reason := "deny-by-default"

# The platform classification ladder; an unknown label maps to no rank and
# is rejected.
rank := {
	"UNCLASSIFIED": 0,
	"PUBLIC": 0,
	"INTERNAL": 1,
	"RESTRICTED": 2,
	"CONFIDENTIAL": 2,
	"SECRET": 3,
	"FIDUCIARY_SEGREGATED": 3,
}

subject_rank := rank[subject_clearance]

subject_clearance := upper(input.subject.clearance) if input.subject.clearance != ""

default subject_clearance := "UNCLASSIFIED"

allow if {
	valid_subject
	resource_rank_known
	subject_rank >= resource_rank
}

valid_subject if input.subject.sub != ""

resource_rank := rank[upper(input.resource.classification)]

resource_rank_known if upper(input.resource.classification) != ""
resource_rank_known if resource_rank >= 0

reason := "allowed" if allow
reason := "insufficient clearance for resource classification" if {
	valid_subject
	resource_rank_known
	subject_rank < resource_rank
}
reason := "unknown resource classification label (fail closed)" if not resource_rank_known
