output "topics" {

  value = {

    for k, v in google_pubsub_topic.topic :

    k => v.id

  }

}



output "subscriptions" {

  value = {

    for k, v in google_pubsub_subscription.subscription :

    k => v.id

  }

}