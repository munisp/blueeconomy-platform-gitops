# CVFF four-party separation-of-duties pack, mirroring the SoD rules the
# financial-controls service embeds (four distinct approving parties for any
# disbursement). At the edge this is a coarse gate: the service remains the
# authoritative enforcer.
package blueeconomy.cvff

import rego.v1

default allow := false

default reason := "deny-by-default"

# The four fiduciary parties whose distinct approvals a CVFF disbursement
# requires (NPA, NIMASA, FMMBE, CBN).
required_parties := {"npa", "nimasa", "fmmbe", "cbn"}

allow if {
	valid_subject
	disbursement_intent_ok
}

valid_subject if input.subject.sub != ""

# A disbursement action must carry approvals from all four distinct parties.
# Duplicate or self-approvals collapse in the set and fail the count.
disbursement_intent_ok if {
	not is_disbursement
}

disbursement_intent_ok if {
	is_disbursement
	approving := {p | some approval in input.resource.approvals; p := lower(approval.party)}
	approving == required_parties
	not self_approval
}

is_disbursement if startswith(input.request.path, "/v1/cvff/disbursements")
is_disbursement if input.resource.action == "disburse"

self_approval if {
	some approval in input.resource.approvals
	approval.approver_sub == input.subject.sub
}

reason := "allowed" if allow
reason := "cvff four-party SoD: approvals from npa, nimasa, fmmbe and cbn are all required" if {
	is_disbursement
	not disbursement_intent_ok
}
reason := "cvff self-approval prohibited" if self_approval
