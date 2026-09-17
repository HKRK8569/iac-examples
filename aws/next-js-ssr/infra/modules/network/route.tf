
# パブリックサブネット用のルートテーブルの定義
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-rt"
    Tier = "public"
  })
}

# Public -> Internet
# publicからinternetの全てをinternetGatewayに流す
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# パブリックサブネットとrouteTableの紐付け
resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# アプリ用プライベートサブネットのルートテーブルの定義
resource "aws_route_table" "app" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-rt-${var.azs[count.index]}"
    Tier = "private-app"
  })
}

# Private -> Internet
# プライベートネットワークからインターネットの全てはnatGatewayを経由して外に出る
# 冗長化OFF（NAT1台）のときは全AZのルートがそのNATを共有する
resource "aws_route" "app_nat" {
  count                  = length(var.azs)
  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[min(count.index, local.nat_count - 1)].id
}

# アプリ用プライベートサブネットとrouteTableの紐付け
resource "aws_route_table_association" "app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# DB用サブネットのルートテーブルの定義
# インターネットへの経路（IGW/NAT）を持たせない。VPC内のローカルルートのみ
# NATがないためAZごとに分ける理由がなく、1つを両AZのサブネットで共有する
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-db-rt"
    Tier = "private-db"
  })
}

# DB用サブネットとrouteTableの紐付け
resource "aws_route_table_association" "db" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
