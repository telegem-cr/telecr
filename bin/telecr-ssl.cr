#!/usr/bin/env crystal
# bin/telecr-ssl.cr - SSL certificate helper for Telecr webhooks

require "file_utils"
require "yaml"

puts " Telecr SSL Setup"

# Check if config already exists
if File.exists?(".telecr-ssl")
puts " SSL config already exists at .telecr-ssl"
print "Overwrite? (y/n): "
input = gets
exit unless input && input.downcase == "y"
end

# Get domain from args or prompt
domain = ARGV[0]?
unless domain
print "Enter domain (e.g., bot.example.com): "
input = gets
if input && !input.empty?
domain = input
else
puts " Domain required"
exit 1
end
end

# Get email from args or prompt
email = ARGV[1]? || "admin@#{domain}"

# Check if certbot is installed
unless system("which certbot > /dev/null", shell: true)
puts "📦 Installing certbot..."
system("sudo apt update && sudo apt install -y certbot", shell: true)
end

# Generate certificate
puts "\n Getting SSL certificate..."
cert_cmd = "sudo certbot certonly --standalone -d #{domain} --email #{email} --agree-tos --non-interactive"
puts "Running: #{cert_cmd}"

if system(cert_cmd, shell: true)
# Create config file
config = {
"domain" => domain,
"cert_path" => "/etc/letsencrypt/live/#{domain}/fullchain.pem",
"key_path" => "/etc/letsencrypt/live/#{domain}/privkey.pem",
"created_at" => Time.utc.to_s
}

File.write(".telecr-ssl", config.to_yaml)
puts " SSL configured! Certificate valid for 90 days."
puts " Config saved to .telecr-ssl"
puts "\n Start your webhook bot with: crystal bot.cr"
else
puts "Failed to get certificate. Check that:"
puts " - Domain #{domain} points to this server"
puts " - Port 80 is not in use (stop web server first)"
puts " - Domain is valid and resolvable"
exit 1
end