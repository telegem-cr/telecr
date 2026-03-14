# markup/keyboard.cr - Reply keyboard markup builders for Telecr

module Telecr
  module Markup
    # ===== Reply Keyboard Helpers =====
    # These create individual button definitions for reply keyboards
    
    module ReplyButtons
      # Create a regular text button
      def text(content, style : String? = nil, icon_custom_emoji_id : String? = nil)
        result = {} of String => JSON::Any
        result["text"] = JSON::Any.new(content)
        if style
          result["style"] = JSON::Any.new(style)
        end
        if icon_custom_emoji_id
          result["icon_custom_emoji_id"] = JSON::Any.new(icon_custom_emoji_id)
        end
        result
      end
      
      # Create a button that requests user's phone number
      def request_contact(text, style : String? = nil, icon_custom_emoji_id : String? = nil)
        result = {} of String => JSON::Any
        result["text"] = JSON::Any.new(text)
        result["request_contact"] = JSON::Any.new(true)
        if style
          result["style"] = JSON::Any.new(style)
        end
        if icon_custom_emoji_id
          result["icon_custom_emoji_id"] = JSON::Any.new(icon_custom_emoji_id)
        end
        result
      end
      
      # Create a button that requests user's location
      def request_location(text, style : String? = nil, icon_custom_emoji_id : String? = nil)
        result = {} of String => JSON::Any
        result["text"] = JSON::Any.new(text)
        result["request_location"] = JSON::Any.new(true)
        if style
          result["style"] = JSON::Any.new(style)
        end
        if icon_custom_emoji_id
          result["icon_custom_emoji_id"] = JSON::Any.new(icon_custom_emoji_id)
        end
        result
      end
      
      # Create a button that creates a poll
      def request_poll(text, poll_type : String? = nil, style : String? = nil, icon_custom_emoji_id : String? = nil)
        result = {} of String => JSON::Any
        result["text"] = JSON::Any.new(text)
        if poll_type
          result["request_poll"] = JSON::Any.new({"type" => poll_type})
        else
          result["request_poll"] = JSON::Any.new({} of String => JSON::Any)
        end
        if style
          result["style"] = JSON::Any.new(style)
        end
        if icon_custom_emoji_id
          result["icon_custom_emoji_id"] = JSON::Any.new(icon_custom_emoji_id)
        end
        result
      end
      
      # Create a web app button
      def web_app(text, url : String? = nil, style : String? = nil, icon_custom_emoji_id : String? = nil)
        result = {} of String => JSON::Any
        result["text"] = JSON::Any.new(text)
        if url
          result["url"] = JSON::Any.new(url)
        end
        if style
          result["style"] = JSON::Any.new(style)
        end
        if icon_custom_emoji_id
          result["icon_custom_emoji_id"] = JSON::Any.new(icon_custom_emoji_id)
        end
        result
      end
    end
    
    # Builder class for creating reply keyboards
    class ReplyBuilder
      include ReplyButtons
      
      def initialize
        @rows = [] of Array(Hash(String, JSON::Any))
        @options = {
          "resize_keyboard" => true,
          "one_time_keyboard" => false,
          "selective" => false
        } of String => (Bool | String)
      end
      
      # Add a row of buttons
      def row(*buttons)
        converted = buttons.to_a.map do |btn|
          # btn is already a Hash(String, JSON::Any) from helper methods
          btn
        end
        @rows << converted
        self
      end
      
      # Set whether keyboard should resize
      def resize(value : Bool = true)
        @options["resize_keyboard"] = value
        self
      end
      
      # Set whether keyboard should hide after use
      def one_time(value : Bool = true)
        @options["one_time_keyboard"] = value
        self
      end
      
      # Set selective mode
      def selective(value : Bool = true)
        @options["selective"] = value
        self
      end
      
      # Set placeholder text
      def placeholder(text : String)
        @options["input_field_placeholder"] = text
        self
      end
      
      # Build the final keyboard
      def build
        ReplyKeyboard.new(@rows, @options)
      end
    end
    
    # Reply keyboard representation
    class ReplyKeyboard
      def initialize(@rows : Array(Array(Hash(String, JSON::Any))), @options : Hash(String, Bool | String))
      end
      
      # Convert to hash for Telegram API
      def to_h : Hash(String, JSON::Any)
        result = {} of String => JSON::Any
        result["keyboard"] = JSON::Any.new(@rows.map do |row|
          JSON::Any.new(row.map do |btn|
            JSON::Any.new(btn)
          end)
        end)
        
        @options.each do |key, value|
          result[key] = JSON::Any.new(value)
        end
        
        result
      end
      
      # Convert to JSON
      def to_json(*args)
        to_h.to_json(*args)
      end
    end
    
    # Factory method for creating reply keyboards
    def self.keyboard(&block : ReplyBuilder ->)
      builder = ReplyBuilder.new
      block.call(builder)
      builder.build
    end
  end
end