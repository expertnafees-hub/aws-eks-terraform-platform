variable "name" { type = string }
variable "vpc_id" { type = string }
variable "api_client_cidrs" { type = set(string) }
resource "aws_security_group" "api_clients" {
  name_prefix = "${var.name}-api-"
  description = "Private EKS API access from approved connected networks"
  vpc_id      = var.vpc_id
}
resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each          = var.api_client_cidrs
  security_group_id = aws_security_group.api_clients.id
  description       = "Approved private API client network"
  cidr_ipv4         = each.key
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
output "api_security_group_id" { value = aws_security_group.api_clients.id }
