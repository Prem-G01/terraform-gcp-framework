resource "google_pubsub_topic" "topic" {

  for_each = var.config.pubsub

  project = var.project_id

  name = each.value.topic.name

  kms_key_name = lookup(
    var.kms_keys,
    lookup(each.value.topic, "kms_key", ""),
    null
  )

  labels = lookup(
    each.value.topic,
    "labels",
    {}
  )

  message_retention_duration = lookup(
    each.value.topic,
    "message_retention_duration",
    "604800s"
  )

}



locals {

  subscriptions = flatten([

    for topic_name, topic in var.config.pubsub : [

      for sub_name, sub in lookup(topic, "subscriptions", {}) : {

        topic_name = topic_name

        sub_key = sub_name

        config = sub

      }

    ]

  ])



  subscriptions_map = {

    for s in local.subscriptions :

    "${s.topic_name}-${s.sub_key}" => s

  }

}



resource "google_pubsub_subscription" "subscription" {

  for_each = local.subscriptions_map



  project = var.project_id



  name = each.value.config.name



  topic = google_pubsub_topic.topic[

    each.value.topic_name

  ].name



  ack_deadline_seconds = lookup(

    each.value.config,

    "ack_deadline_seconds",

    30

  )



  message_retention_duration = lookup(

    each.value.config,

    "message_retention_duration",

    "604800s"

  )



  retain_acked_messages = lookup(

    each.value.config,

    "retain_acked_messages",

    false

  )



  enable_message_ordering = lookup(

    each.value.config,

    "enable_message_ordering",

    false

  )



  dynamic "expiration_policy" {

    for_each = lookup(

      lookup(

        each.value.config,

        "expiration_policy",

        {}

      ),

      "ttl",

      ""

    ) != "" ? [1] : []



    content {

      ttl = each.value.config.expiration_policy.ttl

    }

  }



  dynamic "retry_policy" {

    for_each = lookup(

      each.value.config,

      "retry_policy",

      {}

    ) != {} ? [1] : []



    content {

      minimum_backoff = lookup(

        each.value.config.retry_policy,

        "minimum_backoff",

        "10s"

      )



      maximum_backoff = lookup(

        each.value.config.retry_policy,

        "maximum_backoff",

        "600s"

      )

    }

  }



  dynamic "dead_letter_policy" {

    for_each = lookup(

      lookup(

        each.value.config,

        "dead_letter_policy",

        {}

      ),

      "enabled",

      false

    ) ? [1] : []



    content {

      dead_letter_topic = google_pubsub_topic.topic[

        each.value.config.dead_letter_policy.topic

      ].id



      max_delivery_attempts = lookup(

        each.value.config.dead_letter_policy,

        "max_delivery_attempts",

        5

      )

    }

  }

}