resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id

  # az分natを作成するs
  subnet_id = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-nat-${count.index}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}
