output "jobs" {

  value = {

    for k, v in google_cloud_scheduler_job.job :

    k => v.name

  }

}



output "job_ids" {

  value = {

    for k, v in google_cloud_scheduler_job.job :

    k => v.id

  }

}