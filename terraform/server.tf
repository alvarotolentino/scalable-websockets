resource "latitudesh_server" "server" {
  hostname         = "${var.project_name}-server"
  project          = latitudesh_project.benchmark.id
  plan             = var.server_plan
  site             = var.site
  operating_system = var.os
  ssh_keys         = [latitudesh_ssh_key.deploy.id]
  user_data        = file("${path.module}/templates/server-cloud-init.yaml")
}
