data "aws_availability_zones" "all" {}

locals {
  provisioned_azs = slice(data.aws_availability_zones.all.names, 0, 2)
}

resource "aws_vpc" "test" {
  cidr_block           = "10.254.0.0/20"
  enable_dns_hostnames = true

  tags = {
    Name = "Test VPC"
  }
}

resource "aws_internet_gateway" "direct" {
  vpc_id = aws_vpc.test.id

  tags = {
    Name = "Test Internet GW"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.test.id
}

resource "aws_route" "public-world" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = local.net.world
  gateway_id             = aws_internet_gateway.direct.id
}

resource "aws_subnet" "dmz" {
  count             = length(local.provisioned_azs)
  vpc_id            = aws_vpc.test.id
  availability_zone = local.provisioned_azs[count.index]
  cidr_block        = cidrsubnet("10.254.0.0/24", 2, count.index)
}

resource "aws_route_table_association" "dmz" {
  count          = length(aws_subnet.dmz)
  subnet_id      = aws_subnet.dmz[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_directory_service_directory" "my_directory" {
  name     = "my.workspace"
  password = "dummyPassword99"
  size     = "Small"
  vpc_settings {
    vpc_id     = aws_vpc.test.id
    subnet_ids = aws_subnet.dmz[*].id
  }
  type = "SimpleAD"
}

resource "aws_ec2_client_vpn_endpoint" "the_vpn" {
  server_certificate_arn = "arn:aws:acm:us-east-1:<acctID>:certificate/<certID>"
  client_cidr_block      = "10.254.6.0/22"
  authentication_options {
    type                = "directory-service-authentication"
    active_directory_id = aws_directory_service_directory.my_directory.id
  }
  connection_log_options {
    enabled = false
  }
}

resource "aws_ec2_client_vpn_network_association" "the_vpn_assoc" {
  for_each               = toset(aws_subnet.dmz[*].id)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.the_vpn.id
  subnet_id              = each.value
  lifecycle {
    ignore_changes = [subnet_id, security_groups]
    // the above is a hack - need to test in older version
    // then submit as bug - changes incorrectly detected on sequential runs
  }
}