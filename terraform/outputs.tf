output "server_public_ip" {
  description = "Public IPv4 of the benchmark server"
  value       = latitudesh_server.server.primary_ipv4
}

output "client_public_ips" {
  description = "Public IPv4 addresses of all client machines"
  value       = latitudesh_server.clients[*].primary_ipv4
}

output "project_id" {
  description = "Latitude.sh project ID"
  value       = latitudesh_project.benchmark.id
}
