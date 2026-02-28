resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  for_each   = var.tunnels
  account_id = var.account_id
  name       = each.value.name

  config_src = try(each.value.config_src, null)

  lifecycle {
    prevent_destroy = true
  }
}
