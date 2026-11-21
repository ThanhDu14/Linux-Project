# Bản ghi alias A trỏ các tên miền con (app., status.) vào NLB.
# Hosted zone KHÔNG tạo ở đây: mua domain trên Route53 thì AWS tự tạo zone — environment tìm nó bằng data source.

resource "aws_route53_record" "alias_a" {
  for_each = toset(var.record_names)

  zone_id         = var.route53_zone_id
  name            = each.value
  type            = "A"
  allow_overwrite = true

  alias {
    name    = var.nlb_dns_name
    zone_id = var.nlb_zone_id
    # false: target 443 còn unhealthy khi chưa có Flask (/health) — vẫn muốn tên miền trả về NLB
    evaluate_target_health = false
  }
}
