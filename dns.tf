locals {
  dns_records_effective = {
    for k, r in var.dns_records :
    k => merge(r, (
      r.type == "A" && try(r.comment, "") == "traefik"
      ? { content = var.traefik_ip }
      : {}
    ))
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = local.dns_records_effective

  zone_id  = var.zone_id
  name     = each.value.name
  type     = each.value.type
  ttl      = try(each.value.ttl, 1)
  proxied  = try(each.value.proxied, null)

  content  = try(each.value.content, null)
  data     = try(each.value.data, null)
  priority = try(each.value.priority, null)

  comment  = try(each.value.comment, null)
  tags     = try(each.value.tags, null)

  lifecycle { prevent_destroy = true }
}
