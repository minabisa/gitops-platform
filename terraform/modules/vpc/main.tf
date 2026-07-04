terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get all available AZs in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# The VPC itself — isolated network for the whole platform
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true  # Required for EKS
  enable_dns_support   = true  # Required for EKS

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-vpc"
    # These tags tell EKS this VPC belongs to the cluster
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
  })
}

# Internet Gateway — allows public subnets to reach the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-igw"
  })
}

# Public subnets — where load balancers live
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-public-${count.index + 1}"
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
    "kubernetes.io/role/elb" = "1"  # Tells EKS to use this for public load balancers
  })
}

# Private subnets — where EKS worker nodes live (more secure)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 4)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-private-${count.index + 1}"
    "kubernetes.io/cluster/${var.project}-${var.environment}" = "shared"
    "kubernetes.io/role/internal-elb" = "1"  # Internal load balancers
  })
}

# Elastic IP for NAT Gateway — static IP for outbound traffic
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-nat-eip" })
}

# NAT Gateway — lets private subnet nodes reach the internet (for pulling images)
# Lives in public subnet, uses the EIP
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-nat" })
  depends_on = [aws_internet_gateway.main]
}

# Route table for public subnets — send internet traffic to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-public-rt" })
}

# Route table for private subnets — send internet traffic through NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = merge(var.tags, { Name = "${var.project}-${var.environment}-private-rt" })
}

# Associate route tables with subnets
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
