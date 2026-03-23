resource "latitudesh_project" "benchmark" {
  name        = var.project_name
  environment = var.environment
}

resource "latitudesh_ssh_key" "deploy" {
  name       = "${var.project_name}-deploy-key"
  public_key = var.ssh_public_key
}
