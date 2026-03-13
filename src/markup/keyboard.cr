# markup.cr - Keyboard markup builders for Telecr
# Provides Reply keyboard creation helpers (Inline keyboards to be added)

module Telecr
  module Markup
    # ===== Reply Keyboard Helpers =====
    # These create individual button definitions for reply keyboards
    
    module ReplyButtons
      # Create a regular text button
      #
      # @param content [String] Button text
      # @param style [String?] Button style (e.g., "primary")
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration
      def text(content, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: content,
          icon_custom_emoji_id: icon_custom_emoji_id,
          style: style
        }.reject { |_, v| v.nil? }
      end
      
      # Create a button that requests user's phone number when clicked
      #
      # @param text [String] Button text
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with request_contact flag
      def request_contact(text, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id,
          request_contact: true
        }.reject { |_, v| v.nil? }
      end
      
      # Create a button that requests user's location when clicked
      #
      # @param text [String] Button text
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with request_location flag
      def request_location(text, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id,
          request_location: true
        }.reject { |_, v| v.nil? }
      end
      
      # Create a button that creates a poll when clicked
      #
      # @param text [String] Button text
      # @param poll_type [String?] Poll type ("quiz" or "regular")
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with request_poll options
      def request_poll(text, poll_type : String? = nil, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id,
          request_poll: poll_type ? { type: poll_type } : {} of String => JSON::Any
        }.reject { |_, v| v.nil? }
      end
      
      # Create a button that opens a web app
      #
      # @param text [String] Button text
      # @param url [String?] Web app URL
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with web_app URL
      def web_app(text, url : String? = nil, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          url: url,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
    end
    
    # Builder class for creating reply keyboards with a fluent interface
    class ReplyBuilder
      include ReplyButtons
      
      def initialize
        @rows = [] of Array(Hash(String, JSON::Any))
        @options = {
          resize_keyboard: true,
          one_time_keyboard: false,
          selective: false
        }
      end
      
      # Add a row of buttons to the keyboard
      #
      # @param buttons [Array] Variable number of button definitions
      # @return [self] For method chaining
      def row(*buttons)
        @rows << buttons.to_a
        self
      end
      
      # Set whether keyboard should resize automatically
      #
      # @param value [Bool] Resize flag
      # @return [self] For method chaining
      def resize(value : Bool = true)
        @options[:resize_keyboard] = value
        self
      end
      
      # Set whether keyboard should hide after use
      #
      # @param value [Bool] One-time flag
      # @return [self] For method chaining
      def one_time(value : Bool = true)
        @options[:one_time_keyboard] = value
        self
      end
      
      # Set whether keyboard affects only specific users
      #
      # @param value [Bool] Selective flag
      # @return [self] For method chaining
      def selective(value : Bool = true)
        @options[:selective] = value
        self
      end
      
      # Set placeholder text shown in input field
      #
      # @param text [String] Placeholder text
      # @return [self] For method chaining
      def placeholder(text : String)
        @options[:input_field_placeholder] = text
        self
      end
      
      # Build the final keyboard object
      #
      # @return [ReplyKeyboard] The constructed keyboard
      def build
        ReplyKeyboard.new(@rows, @options)
      end
    end
    
    # Reply keyboard representation that can be converted to JSON
    class ReplyKeyboard
      def initialize(@rows : Array(Array(Hash(String, JSON::Any))), @options : Hash(Symbol, Bool | String))
      end
      
      # Convert to hash for Telegram API
      #
      # @return [Hash] Telegram-compatible keyboard hash
      def to_h
        base = {keyboard: @rows}
        @options.each_with_object(base) do |(k, v), hash|
          hash[k] = v
        end
      end
      
      # Convert to JSON for API calls
      def to_json(*args)
        to_h.to_json(*args)
      end
    end
    
    # Factory method for creating reply keyboards
    #
    # @example
    #   keyboard = Telecr::Markup.keyboard do |k|
    #     k.row(text("Yes"), text("No"))
    #     k.row(request_location("Send location"))
    #     k.resize.one_time
    #   end
    #
    # @return [ReplyKeyboard] The constructed keyboard
    def self.keyboard(&block : ReplyBuilder ->)
      builder = ReplyBuilder.new
      block.call(builder)
      builder.build
    end
  end
end