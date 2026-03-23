resource "latitudesh_server" "clients" {
  count = var.client_count

  hostname         = "${var.project_name}-client-${count.index}"
  project          = latitudesh_project.benchmark.id
  plan             = var.client_plan
  site             = var.site
  operating_system = var.os
  ssh_keys         = [latitudesh_ssh_key.deploy.id]
  user_data        = file("${path.module}/templates/client-cloud-init.yaml")
}
