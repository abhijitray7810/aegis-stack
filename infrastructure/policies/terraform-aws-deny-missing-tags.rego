package terraform.aws.deny_missing_tags

import future.keywords.in
import future.keywords.if

required_tags := {"Project", "Environment", "ManagedBy", "Owner"}

# Collect resources that are missing at least one required tag
deny[msg] if {
  resource := input.resource_changes[_]
  resource.change.actions[_] in {"create", "update"}

  # Only check taggable resource types
  startswith(resource.type, "aws_")
  not exempt_resource(resource.type)

  tags := object.get(resource.change.after, "tags", {})
  missing := required_tags - {k | tags[k]}
  count(missing) > 0

  msg := sprintf(
    "Resource '%s' (%s) is missing required tags: %v",
    [resource.address, resource.type, missing]
  )
}

# Resource types exempt from tag requirements
exempt_resource(t) if {
  t in {
    "aws_iam_role_policy_attachment",
    "aws_iam_policy_attachment",
    "aws_kms_alias",
  }
}
