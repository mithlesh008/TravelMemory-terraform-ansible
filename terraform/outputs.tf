output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}

output "db_private_ip" {
  value = aws_instance.database.private_ip
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}
