output "queues" {

  value = {

    for k, v in google_cloud_tasks_queue.queue :

    k => v.name

  }

}



output "queue_ids" {

  value = {

    for k, v in google_cloud_tasks_queue.queue :

    k => v.id

  }

}