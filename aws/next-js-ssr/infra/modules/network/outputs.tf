# vpc
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR"
  value       = aws_vpc.this.cidr_block
}

# subnets
output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "Private Subnet IDs (app: ECS・踏み台用)"
  value       = aws_subnet.app[*].id
}

output "db_subnet_ids" {
  description = "DB Subnet IDs (Aurora用)"
  value       = aws_subnet.db[*].id
}

output "public_subnet_cidrs" {
  description = "Public Subnet CIDRs"
  value       = aws_subnet.public[*].cidr_block
}

output "app_subnet_cidrs" {
  description = "Private Subnet CIDRs (app)"
  value       = aws_subnet.app[*].cidr_block
}

output "db_subnet_cidrs" {
  description = "DB Subnet CIDRs"
  value       = aws_subnet.db[*].cidr_block
}

# internetGateway
output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.this.id
}

# nat/eip
output "nat_gateway_ids" {
  description = "NAT Gateway IDs (per AZ)"
  value       = aws_nat_gateway.this[*].id
}

output "nat_eip_allocation_ids" {
  description = "EIP Allocation IDs for NAT"
  value       = aws_eip.nat[*].id
}

output "nat_eip_public_ips" {
  description = "Public IPs of NAT EIPs"
  value       = aws_eip.nat[*].public_ip
}

# routeTable
output "public_route_table_id" {
  description = "Public Route Table ID"
  value       = aws_route_table.public.id
}

output "app_route_table_ids" {
  description = "Private Route Table IDs (app, per AZ)"
  value       = aws_route_table.app[*].id
}

output "db_route_table_id" {
  description = "DB Route Table ID (NATルートなし・両AZ共有)"
  value       = aws_route_table.db.id
}

# defaultResource
output "default_route_table_id" {
  description = "Default Route Table ID"
  value       = aws_default_route_table.default.id
}

output "default_security_group_id" {
  description = "Default Security Group ID"
  value       = aws_default_security_group.default.id
}

output "default_network_acl_id" {
  description = "Default Network ACL ID"
  value       = aws_default_network_acl.default.id
}
