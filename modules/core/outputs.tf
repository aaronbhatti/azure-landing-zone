# Core Module Outputs - ALZ Governance

output "management_groups" {
  description = "ALZ management groups"
  value       = try(module.alz.management_groups, {})
}

output "policy_assignments" {
  description = "ALZ policy assignments"
  value       = try(module.alz.policy_assignments, {})
}

output "policy_definitions" {
  description = "ALZ policy definitions"
  value       = try(module.alz.policy_definitions, {})
}

output "role_assignments" {
  description = "ALZ role assignments"
  value       = try(module.alz.role_assignments, {})
}
