resource "cloudflare_email_routing_settings" "this" {
  zone_id = var.zone_id
  lifecycle { prevent_destroy = true }
}

resource "cloudflare_email_routing_address" "this" {
  for_each = var.email_routing_addresses

  account_id = var.account_id
  email      = each.value.email

  lifecycle { prevent_destroy = true }
}

resource "cloudflare_email_routing_rule" "this" {
  for_each = var.email_routing_rules

  zone_id  = var.zone_id
  name     = each.value.name
  enabled  = each.value.enabled
  priority = each.value.priority
  actions  = each.value.actions
  matchers = each.value.matchers

  lifecycle { prevent_destroy = true }
}

resource "cloudflare_email_routing_address" "extra" {
  for_each   = var.email_routing_addresses_extra
  account_id = var.account_id
  email      = each.value.email
  lifecycle { prevent_destroy = true }
}

resource "cloudflare_email_routing_rule" "extra" {
  for_each = var.email_routing_rules_extra
  zone_id  = var.zone_id
  name     = each.value.name
  enabled  = try(each.value.enabled, true)
  priority = try(each.value.priority, null)
  actions  = each.value.actions
  matchers = each.value.matchers
  lifecycle { prevent_destroy = true }
}

resource "cloudflare_email_routing_catch_all" "this" {
  zone_id  = var.zone_id
  enabled  = var.email_routing_catch_all.enabled
  name     = var.email_routing_catch_all.name
  actions  = var.email_routing_catch_all.actions
  matchers = var.email_routing_catch_all.matchers

  lifecycle { prevent_destroy = true }
}
