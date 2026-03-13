# webhook/server.cr - Webhook server for Telecr bots
# Handles HTTPS webhook connections from Telegram

require "http/server"
require "file_utils"
require "yaml"
require "openssl"
require "json"
require "uri"

module Telecr
  module Webhook
    # Webhook server that listens for Telegram updates via HTTPS
    class Server
      # Core properties
      getter bot : Bot
      getter port : Int32
      getter host : String
      getter logger : Logger
      getter secret_token : String
      getter running : Bool
      getter server : HTTP::Server?
      getter ssl_mode : Symbol
      getter ssl_context : OpenSSL::SSL::Context::Server?
      
      def initialize(
        @bot : Bot,
        @port : Int32? = nil,
        @host : String = "0.0.0.0",
        @secret_token : String? = nil,
        logger : Logger? = nil,
        ssl : (Bool | Hash(Symbol, String))? = nil
      )
        # Set up logging
        @logger = logger || Log.for("telecr.api")
        @logger.level = Logger::INFO
        
        # Set port from param, env, or default
        @port = port || ENV["PORT"]?.try(&.to_i) || 3000
        
        # Generate secret token if not provided (for webhook security)
        @secret_token = secret_token || Random::Secure.hex(16)
        
        @running = false
        @server = nil
        
        # Determine SSL mode
        ssl_result = determine_ssl_mode(ssl)
        @ssl_mode = ssl_result[0]
        @ssl_context = ssl_result[1]
        
        log_configuration
        validate_ssl_setup
      end
      
      # Determine SSL mode based on options and config files
      #
      # @param ssl_options [Bool | Hash(Symbol, String)?] SSL configuration
      # @return [Tuple(Symbol, OpenSSL::SSL::Context::Server?)] SSL mode and context
      private def determine_ssl_mode(ssl_options : (Bool | Hash(Symbol, String))?)
        # Option 1: Explicitly disabled
        if ssl_options == false
          return {:none, nil}
        end
        
        # Option 2: Try loading from .telecr-ssl config file (created by telecr-ssl tool)
        if File.exists?(".telecr-ssl")
          begin
            config = YAML.parse(File.read(".telecr-ssl"))
            cert_path = config["cert_path"]?.try(&.to_s)
            key_path = config["key_path"]?.try(&.to_s)
            
            if cert_path && key_path && File.exists?(cert_path) && File.exists?(key_path)
              context = load_certificate_files(cert_path, key_path)
              return {:cli, context} if context
            end
          rescue e
            @logger.warn("Failed to load .telecr-ssl config: #{e.message}")
          end
        end
        
        # Option 3: Manual SSL via options hash
        if ssl_options.is_a?(Hash)
          cert_path = ssl_options[:cert_path]?
          key_path = ssl_options[:key_path]?
          
          if cert_path && key_path && File.exists?(cert_path) && File.exists?(key_path)
            context = load_certificate_files(cert_path, key_path)
            return {:manual, context} if context
          end
        end
        
        # Option 4: Cloud SSL (using reverse proxy like nginx)
        if ENV["TELECR_WEBHOOK_URL"]?
          begin
            url = URI.parse(ENV["TELECR_WEBHOOK_URL"])
            if url.scheme == "https"
              return {:cloud, nil}
            end
          rescue
            # Invalid URL, ignore
          end
        end
        
        # Default: no SSL
        {:none, nil}
      end
      
      # Load certificate files and create SSL context
      #
      # @param cert_path [String] Path to certificate file
      # @param key_path [String] Path to private key file
      # @return [OpenSSL::SSL::Context::Server?] SSL context or nil on failure
      private def load_certificate_files(cert_path : String, key_path : String) : OpenSSL::SSL::Context::Server?
        begin
          context = OpenSSL::SSL::Context::Server.new
          context.certificate_chain = cert_path
          context.private_key = key_path
          context
        rescue e
          @logger.error("Failed to load SSL certificates: #{e.message}")
          nil
        end
      end
      
      # Log current configuration
      private def log_configuration
        @logger.info("Webhook server configured:")
        @logger.info("  Host: #{@host}")
        @logger.info("  Port: #{@port}")
        @logger.info("  SSL Mode: #{@ssl_mode}")
        @logger.info("  Secret Token: #{@secret_token[0..7]}...")
      end
      
      # Validate SSL setup is correct
      private def validate_ssl_setup
        case @ssl_mode
        when :none
          @logger.warn("Running without SSL. Telegram requires HTTPS for webhooks.")
          @logger.warn("   Use telecr-ssl tool or set up a reverse proxy.")
        when :cli, :manual
          @logger.info("SSL configured using local certificates")
        when :cloud
          @logger.info("SSL handled by cloud proxy (nginx/Cloudflare)")
        end
      end
      
      # Start the webhook server
#
# @return [nil]
def run
  # Don't start if already running
  return if @running
  
  case @ssl_mode
  when :cli, :manual
    @logger.info("Starting webhook server with local certificates")
    @server = HTTP::Server.new(
      ssl: @ssl_context,
      host: @host,
      port: @port
    ) do |context|
      handle_request(context)
    end
  when :cloud
    @logger.info("Starting server with cloud platform (SSL handled by proxy)")
    @server = HTTP::Server.new(
      host: @host,
      port: @port
    ) do |context|
      handle_request(context)
    end
  else
    @logger.error("Server won't start without valid SSL")
    @logger.error("Telegram requires HTTPS for webhooks")
    return
  end
  
  @running = true
  
  # Start server in background fiber
  spawn do
    @server.not_nil!.listen
  end
  
  # Register webhook with Telegram
  set_telegram_webhook
end

# Handle incoming HTTP requests
#
# @param context [HTTP::Server::Context] The HTTP request context
# @return [nil]
def handle_request(context : HTTP::Server::Context)
  # Check if path matches secret token (security measure)
  if context.request.path == "/#{@secret_token}"
    handle_webhook_request(context)
  elsif context.request.path == "/health" || context.request.path == "/healthz"
    health_endpoint(context)
  else
    # Return 404 for unknown paths
    context.response.status_code = 404
    context.response.print("Not Found")
  end
end

# Health check endpoint for monitoring services
#
# @param context [HTTP::Server::Context] The HTTP request context
# @return [nil]
def health_endpoint(context : HTTP::Server::Context)
  context.response.status_code = 200
  context.response.print("OK")
end

# Process incoming webhook from Telegram
#
# @param context [HTTP::Server::Context] The HTTP request context
# @return [nil]
def handle_webhook_request(context : HTTP::Server::Context)
  # Read request body
  body = context.request.body.try(&.gets_to_end)
  
  if body
    begin
      # Parse JSON update
      update_data = JSON.parse(body)
      
      # Process with bot
      @bot.process(update_data)
      
      # Acknowledge receipt
      context.response.status_code = 200
      context.response.print("OK")
    rescue e
      @logger.error("Failed to process webhook: #{e.message}")
      context.response.status_code = 500
      context.response.print("Internal Server Error")
    end
  else
    @logger.warn("Empty webhook request received")
    context.response.status_code = 400
    context.response.print("Empty request")
  end
end

# Register webhook URL with Telegram
#
# @return [nil]
        
      # Stop the webhook server gracefully
#
# @return [nil]
def stop
  return unless @running
  @running = false
  
  # Close server only if it exists 
  if server = @server
    server.close
    @server = nil
  end
end
      
    


# Generate the full webhook URL based on SSL mode
#
# @return [String] The complete webhook URL including secret token
def webhook_url : String
  case @ssl_mode
  when :cli, :manual
    # HTTPS with local certificates
    "https://#{@host}:#{@port}/#{@secret_token}"
  when :cloud
    # Cloud platform handles SSL (Heroku, Render, Railway, etc.)
    base_url = ENV["TELECR_WEBHOOK_URL"]?.to_s.chomp('/')
    
    if base_url.empty?
      @logger.warn("⚠️ TELECR_WEBHOOK_URL not set, webhook may not work")
      return "https://#{@host}:#{@port}/#{@secret_token}"
    end
    
    "#{base_url}/#{@secret_token}"
  else
    # No SSL - HTTP (will not work with Telegram)
    @logger.warn("  Using HTTP without SSL - Telegram requires HTTPS")
    "http://#{@host}:#{@port}/#{@secret_token}"
  end
end

# Set the webhook URL with Telegram
#
# @param options [Hash] Additional webhook options
# @option options [Int32] :max_connections (40) Maximum simultaneous connections
# @option options [Array(String)] :allowed_updates Update types to receive
# @option options [Int32] :drop_pending_updates Drop pending updates on set
# @return [String] The webhook URL that was set
def set_webhook(**options)
  url = webhook_url
  params = { url: url }.merge(options)
  
  @logger.info(" Setting webhook to: #{url}")
  
  begin
    @bot.set_webhook(**params)
    @logger.info(" Webhook successfully configured")
  rescue e
    @logger.error(" Failed to set webhook: #{e.message}")
  end
  
  url
end

# Delete the current webhook
#
# @return [nil]
def delete_webhook
  @logger.info("Deleting webhook")
  
  begin
    @bot.delete_webhook
    @logger.info(" Webhook deleted successfully")
  rescue e
    @logger.error(" Failed to delete webhook: #{e.message}")
  end
end

# Get current webhook information from Telegram
#
# @return [JSON::Any] Webhook status information
def get_webhook_info
  @logger.info(" Fetching webhook information")
  
  begin
    result = @bot.get_webhook_info
    @logger.info(" Webhook info retrieved")
    result
  rescue e
    @logger.error("❌ Failed to get webhook info: #{e.message}")
    JSON.parse(%({"ok": false, "error": "#{e.message}"}))
  end
end

# Check if server is currently running
#
# @return [Bool] True if server is active
     def running?
       @running 
     end 
   end 
 end 
 end
