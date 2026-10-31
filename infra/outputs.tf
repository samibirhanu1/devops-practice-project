output "public_ip" {
  description = "Public IP address of the server"
  value       = aws_instance.app.public_ip
}

output "ssh_command" {
  description = "How to log in as deployer (after the first-boot script has finished)"
  value       = "ssh -i <path-to-private-key> deployer@${aws_instance.app.public_ip}"
}