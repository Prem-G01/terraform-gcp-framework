output "workflows" {

  value = {

    for k, v in google_workflows_workflow.workflow :

    k => v.name

  }

}



output "workflow_ids" {

  value = {

    for k, v in google_workflows_workflow.workflow :

    k => v.id

  }

}