# Data Sources for Azure Landing Zone

# Get current public IP address for administrative access to network-restricted resources
# This IP is automatically added to allow lists for storage accounts and other services
data "http" "ip" {
  url = "https://api.ipify.org/"
  retry {
    attempts     = 5
    max_delay_ms = 1000
    min_delay_ms = 500
  }
}

# Additional data sources can be added here as the project grows
# Examples:
# - Azure client configuration
# - Existing resource lookups
# - External API calls for configuration