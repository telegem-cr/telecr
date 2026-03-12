# plugins/upload.cr - File upload plugin for Telecr
# Automatically downloads files from Telegram and uploads to shrine storage

module Telecr
  module Plugins
    # Upload plugin handles file downloading and external storage
    #
    # When users send photos, documents, videos, etc., this plugin:
    # 1. Downloads the file from Telegram
    # 2. Uploads it to shrine (or any storage)
    # 3. Adds shrine URL/file info to context for handlers
    #
    # @example Basic usage
    #   bot.use(Telecr::Plugins::Upload.new(
    #     shrine: shrine_instance,
    #     auto_download: true
    #   ))
    #
    # @example With options
    #   bot.use(Telecr::Plugins::Upload.new(
    #     shrine: shrine_instance,
    #     auto_download: true,
    #     allowed_types: ["photo", "document"],
    #     max_size: 20 * 1024 * 1024,  # 20MB
    #     storage_path: ->(ctx, file_id) { "telegram/#{ctx.chat.id}/#{file_id}" }
    #   ))
    class Upload < Core::Middleware
      # Initialize upload plugin
      #
      # @param shrine [Object] Shrine storage instance (must respond to #upload)
      # @param auto_download [Bool] Whether to auto-download files (default: true)
      # @param allowed_types [Array(String)] File types to process
      # @param max_size [Int64] Maximum file size in bytes (default: 20MB)
      # @param storage_path [Proc(Core::Context, String -> String)] Custom path generator
      def initialize(
        @shrine : Object,
        @auto_download : Bool = true,
        @allowed_types : Array(String) = ["photo", "document", "video", "audio", "voice", "sticker"],
        @max_size : Int64 = 20 * 1024 * 1024,  # 20MB default
        @storage_path : (Core::Context, String -> String)? = nil
      )
        @logger = Logger.new(STDOUT)
        @logger.info("📎 Upload plugin initialized")
      end
      
      # Middleware call - processes files in updates
      #
      # @param ctx [Core::Context] Current context
      # @param next_mw [Proc(Core::Context ->)] Next middleware
      # @return [Any] Result from chain
      def call(ctx : Core::Context, next_mw : Core::Context ->)
        # Process files if this update has any
        if @auto_download && has_file?(ctx)
          process_files(ctx)
        end
        
        # Continue chain
        next_mw.call(ctx)
      end
      
      private
      
      # Check if update contains downloadable files
      #
      # @param ctx [Core::Context] Current context
      # @return [Bool] True if has files
      def has_file?(ctx : Core::Context) : Bool
        return true if ctx.message&.photo
        return true if ctx.message&.document
        return true if ctx.message&.video
        return true if ctx.message&.audio
        return true if ctx.message&.voice
        return true if ctx.message&.sticker
        false
      end
      
      # Process all files in the update
      #
      # @param ctx [Core::Context] Current context
      # @return [nil]
      def process_files(ctx : Core::Context)
        # Handle photos (array of sizes)
        if photos = ctx.message&.photo
          # Get largest photo
          largest = photos.max_by? { |p| p.file_size.to_i64 }
          process_file(ctx, largest, "photo") if largest
        end
        
        # Handle document
        if doc = ctx.message&.document
          process_file(ctx, doc, "document") if allowed?("document")
        end
        
        # Handle video
        if video = ctx.message&.video
          process_file(ctx, video, "video") if allowed?("video")
        end
        
        # Handle audio
        if audio = ctx.message&.audio
          process_file(ctx, audio, "audio") if allowed?("audio")
        end
        
        # Handle voice
        if voice = ctx.message&.voice
          process_file(ctx, voice, "voice") if allowed?("voice")
        end
        
        # Handle sticker
        if sticker = ctx.message&.sticker
          process_file(ctx, sticker, "sticker") if allowed?("sticker")
        end
      end
      
      # Process a single file
      #
      # @param ctx [Core::Context] Current context
      # @param file [Object] File object from Telegram
      # @param type [String] File type
      # @return [nil]
      def process_file(ctx : Core::Context, file, type : String)
        file_id = file.file_id.to_s
        file_size = file.file_size.to_i64
        
        # Check size limit
        if file_size > @max_size
          @logger.warn("File too large: #{file_size} bytes (max: #{@max_size})")
          ctx.state[:upload_error] = "File too large"
          return
        end
        
        @logger.debug("Processing #{type} file: #{file_id}")
        
        begin
          # Download from Telegram
          temp_path = download_telegram_file(ctx, file_id)
          
          # Generate storage path
          storage_path = generate_storage_path(ctx, file_id, file, type)
          
          # Upload to shrine
          result = upload_to_shrine(temp_path, storage_path, file, type)
          
          # Store result in context for handlers
          store_result(ctx, type, result, file)
          
          # Clean up temp file
          File.delete(temp_path) if File.exists?(temp_path)
          
        rescue e
          @logger.error("Failed to process file #{file_id}: #{e.message}")
          ctx.state[:upload_error] = e.message
        end
      end
      
      # Download file from Telegram
      #
      # @param ctx [Core::Context] Current context
      # @param file_id [String] Telegram file ID
      # @return [String] Path to downloaded temp file
      def download_telegram_file(ctx : Core::Context, file_id : String) : String
        # Create temp file
        temp_file = File.tempfile("telecr-upload", ".tmp")
        temp_path = temp_file.path
        
        # Download using bot client
        ctx.bot.client.download(file_id, temp_path)
        
        temp_path
      end
      
      # Generate storage path for file
      #
      # @param ctx [Core::Context] Current context
      # @param file_id [String] Telegram file ID
      # @param file [Object] File object
      # @param type [String] File type
      # @return [String] Storage path
      def generate_storage_path(ctx : Core::Context, file_id : String, file, type : String) : String
        # Use custom path generator if provided
        if custom = @storage_path
          return custom.call(ctx, file_id)
        end
        
        # Default path: telegram/chat_id/type/file_id.ext
        chat_id = ctx.chat?.try(&.id) || "unknown"
        ext = file.file_name.to_s.split('.').last? || "bin"
        
        "telegram/#{chat_id}/#{type}/#{file_id}.#{ext}"
      end
      
      # Upload file to shrine
      #
      # @param temp_path [String] Path to downloaded file
      # @param storage_path [String] Destination path in shrine
      # @param file [Object] Original file object
      # @param type [String] File type
      # @return [Object] Shrine upload result
      def upload_to_shrine(temp_path : String, storage_path : String, file, type : String)
        # Open file and upload
        File.open(temp_path) do |io|
          metadata = {
            "filename" => file.file_name?.to_s || "unknown",
            "size" => file.file_size.to_s,
            "mime_type" => file.mime_type?.to_s || "application/octet-stream",
            "telegram_type" => type,
            "telegram_file_id" => file.file_id.to_s
          }
          
          @shrine.upload(io, storage_path, metadata: metadata)
        end
      end
      
      # Store upload result in context for handlers
      #
      # @param ctx [Core::Context] Current context
      # @param type [String] File type
      # @param result [Object] Shrine upload result
      # @param file [Object] Original file object
      # @return [nil]
      def store_result(ctx : Core::Context, type : String, result, file)
        ctx.state[:upload] ||= {} of String => JSON::Any
        
        upload_info = {
          "type" => type,
          "file_id" => file.file_id.to_s,
          "shrine_id" => result.id.to_s,
          "shrine_url" => result.url.to_s,
          "filename" => file.file_name?.to_s || "unknown",
          "size" => file.file_size.to_i64
        }
        
        # Convert to JSON::Any for state storage
        ctx.state[:upload][type] = upload_info.to_json.as(JSON::Any)
        
        # Also provide convenience accessor
        ctx.state[:uploaded_file] = result
      end
      
      # Check if file type is allowed
      #
      # @param type [String] File type
      # @return [Bool] True if allowed
      def allowed?(type : String) : Bool
        @allowed_types.includes?(type)
      end
    end
  end
end