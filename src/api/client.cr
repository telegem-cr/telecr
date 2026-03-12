# client.cr - Telegram Bot API Client for Crystal
# Handles all communication with Telegram servers

require "http/client"
require "json"
require "http/form-data"
require "logger"

module Telegem
  # API module contains all Telegram API interaction classes
  module Api
    # Main client class for making requests to Telegram Bot API
    class Client
      # Initialize a new Telegram bot client
      # 
      # @param token [String] Bot token from @BotFather
      # @param options [Hash] Optional configuration
      # @option options [Int32] :timeout Request timeout in seconds (default 30)
      def initialize(token : String, **options)
        @token = token
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::INFO
        
        # Set timeout from options or default to 30 seconds
        @timeout = options[:timeout]? || 30
        
        # Create HTTPS client for api.telegram.org
        @http = HTTP::Client.new("api.telegram.org", tls: true)
        @http.read_timeout = @timeout
      end 
      
      # Make a blocking API call (raises on error)
      # 
      # @param method [String] Telegram API method name (e.g., "sendMessage")
      # @param params [Hash(String, String)] Method parameters
      # @return [JSON::Any] API response result
      # @raise [APIError] If Telegram returns error
      def call(method : String, params = {} of String => String) : JSON::Any
        make_request(method, params)
      end 
      
      # Make an API call with callback block (non-blocking style)
      # 
      # @param method [String] Telegram API method name
      # @param params [Hash(String, String)] Method parameters
      # @yield [JSON::Any?, Exception?] Passes result or error to block
      def call!(method : String, params = {} of String => String, &block : (JSON::Any?, Exception?) ->)
        begin
          result = make_request(method, params)
          block.call(result, nil)
        rescue error
          block.call(nil, error)
        end 
      end 
      
      # Upload a file using multipart/form-data
      # 
      # @param method [String] Upload method (sendPhoto, sendDocument, etc.)
      # @param params [Hash(String, String)] Parameters including file paths
      # @return [JSON::Any] API response result
      def upload(method : String, params : Hash(String, String)) : JSON::Any
        url = "/bot#{@token}/#{method}"
        
        # Build multipart form data
        builder = HTTP::FormData::Builder.new
        
        params.each do |k, v|
          if file_object?(v)
            # Add file field
            builder.file(k.to_s, v.to_s) do |file|
              # Set content type based on file extension
              ext = File.extname(v.to_s).downcase
              file.content_type = case ext
              when ".jpg", ".jpeg" then "image/jpeg"
              when ".png" then "image/png"
              when ".mp4" then "video/mp4"
              when ".pdf" then "application/pdf"
              else "application/octet-stream"
              end
            end
          else
            # Add regular text field
            builder.field(k.to_s, v.to_s)
          end
        end
        
        form = builder.finish
        headers = HTTP::Headers{"Content-Type" => form.content_type}
        response = @http.post(url, headers: headers, body: form)
        handle_response(response)
      end 
      
      # Download a file from Telegram servers
      # 
      # @param file_id [String] Telegram file_id from message
      # @param destination_path [String?] Where to save file (optional)
      # @return [String] File content if no destination, otherwise path
      # @raise [NetworkError] If download fails
      def download(file_id : String, destination_path : String? = nil) : String?
        # First get file info from Telegram
        file_info = call("getFile", {"file_id" => file_id})
        return nil unless file_info && file_info["file_path"]?
        
        # Construct download URL
        file_path = file_info["file_path"].to_s
        download_url = "/file/bot#{@token}/#{file_path}"
        
        # Download the file
        response = @http.get(download_url)
        
        if response.success?
          content = response.body_io.gets_to_end
          if destination_path
            # Save to file
            File.write(destination_path, content)
            destination_path
          else
            # Return raw content
            content
          end
        else
          raise NetworkError.new("Download failed: HTTP #{response.status_code}")
        end
      end
      
      # Get updates from Telegram (long polling)
      # 
      # @param offset [Int32?] Last update ID + 1
      # @param timeout [Int32] Long polling timeout in seconds
      # @param limit [Int32] Max number of updates to receive
      # @param allowed_updates [Array(String)?] Which update types to receive
      # @return [JSON::Any] Array of updates
      def get_updates(
        offset : Int32? = nil,
        timeout : Int32 = 30,
        limit : Int32 = 100,
        allowed_updates : Array(String)? = nil
      ) : JSON::Any
        params = {
          "timeout" => timeout.to_s,
          "limit" => limit.to_s
        }
        params["offset"] = offset.to_s if offset
        params["allowed_updates"] = allowed_updates.to_json if allowed_updates
        
        call("getUpdates", params)
      end
      
      # Make the actual HTTP request to Telegram
      # 
      # @param method [String] API method name
      # @param params [Hash(String, String)] Request parameters
      # @return [JSON::Any] Parsed response result
      # @raise [APIError] If Telegram returns error
      private def make_request(method : String, params : Hash(String, String)) : JSON::Any
        url = "/bot#{@token}/#{method}"
        @logger.debug("API call #{method}") if @logger
        
        # Send POST request with JSON body
        response = @http.post(
          url,
          headers: HTTP::Headers{"Content-Type" => "application/json"},
          body: params.to_json
        )
        
        handle_response(response)
      end
      
      # Parse and validate Telegram API response
      # 
      # @param response [HTTP::Client::Response] Raw HTTP response
      # @return [JSON::Any] The result field from Telegram
      # @raise [APIError] If Telegram returns error status
      private def handle_response(response : HTTP::Client::Response) : JSON::Any
        # Read response body
        body = response.body_io.gets_to_end
        json = JSON.parse(body)
        
        # Check if request was successful
        if json["ok"].as_bool
          json["result"]
        else
          desc = json["description"]?.try(&.to_s) || "API Error"
          code = json["error_code"]?.try(&.as_i)
          raise APIError.new(desc, code)
        end
      end
      
      # Check if a value represents a file that needs multipart upload
      # 
      # @param obj [String] Value to check
      # @return [Bool] True if object is a file or file path
      private def file_object?(obj : String) : Bool
        File.exists?(obj)
      end
      
      # Overload for non-string objects
      private def file_object?(obj) : Bool
        obj.is_a?(File) || obj.is_a?(IO)
      end
    end
    
    # Custom error for Telegram API failures
    class APIError < Exception
      # HTTP error code from Telegram
      getter code : Int32?
      
      def initialize(message : String, @code = nil)
        super(message)
      end
    end
    
    # Network-related errors (timeouts, connection issues)
    class NetworkError < APIError; end
  end
end