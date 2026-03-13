# markup_inline.cr - Inline keyboard markup builders for Telecr
# Provides inline keyboard creation helpers for messages

module Telecr
  module Markup
    # ===== Inline Keyboard Helpers =====
    # These create individual inline button definitions
    
    module InlineButtons
      # Create a button that sends a callback query when pressed
      #
      # @param text [String] Button text
      # @param data [String] Callback data (sent to bot when pressed)
      # @param style [String?] Button style (e.g., "primary")
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with callback_data
      def callback(text, data, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          callback_data: data,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
      
      # Create a button that opens a URL when pressed
      #
      # @param text [String] Button text
      # @param url [String] URL to open
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with url
      def url(text, url, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          url: url,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
      
      # Create a button that switches to inline mode
      #
      # @param text [String] Button text
      # @param query [String?] Inline query to insert
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with switch_inline_query
      def switch_inline(text, query : String? = nil, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          switch_inline_query: query,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
      
      # Create a button that switches to inline mode in current chat
      #
      # @param text [String] Button text
      # @param query [String?] Inline query to insert
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with switch_inline_query_current_chat
      def switch_inline_current_chat(text, query : String? = nil, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          switch_inline_query_current_chat: query,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
      
      # Create a button that launches a game
      #
      # @param text [String] Button text
      # @param game_short_name [String] Game short name
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with callback_game
      def callback_game(text, game_short_name, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          callback_game: { game_short_name: game_short_name },
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
      
      # Create a payment button
      #
      # @param text [String] Button text
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with pay flag
      def pay(text, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          pay: true,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
      
      # Create a web app button
      #
      # @param text [String] Button text
      # @param url [String?] Web app URL
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @return [Hash] Button configuration with web_app
      def web_app(text, url : String? = nil, style : String? = nil, icon_custom_emoji_id : String? = nil)
        {
          text: text,
          web_app: { url: url },
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
      
      # Create a login button
      #
      # @param text [String] Button text
      # @param url [String] Login URL
      # @param style [String?] Button style
      # @param icon_custom_emoji_id [String?] Custom emoji ID
      # @param options [Hash] Additional login URL options
      # @return [Hash] Button configuration with login_url
      def login(text, url, style : String? = nil, icon_custom_emoji_id : String? = nil, **options)
        login_url = { url: url }.merge(options)
        {
          text: text,
          login_url: login_url,
          style: style,
          icon_custom_emoji_id: icon_custom_emoji_id
        }.reject { |_, v| v.nil? }
      end
    end
    
    # Builder class for creating inline keyboards with a fluent interface
    class InlineBuilder
      include InlineButtons
      
      def initialize
        @rows = [] of Array(Hash(String, JSON::Any))
      end
      
      # Add a row of inline buttons
      #
      # @param buttons [Array] Variable number of button definitions
      # @return [self] For method chaining
      def row(*buttons)
        @rows << buttons.to_a
        self
      end
      
      # Build the final inline keyboard
      #
      # @return [InlineKeyboard] The constructed keyboard
      def build
        InlineKeyboard.new(@rows)
      end
    end
    
    # Inline keyboard representation that can be converted to JSON
    class InlineKeyboard
      getter rows : Array(Array(Hash(String, JSON::Any)))
      
      def initialize(@rows)
      end
      
      # Convert to hash for Telegram API
      #
      # @return [Hash] Telegram-compatible inline keyboard hash
      def to_h
        {
          inline_keyboard: @rows
        }
      end
      
      # Convert to JSON for API calls
      def to_json(*args)
        to_h.to_json(*args)
      end
    end
    
    # Factory method for creating inline keyboards
    #
    # @example
    #   keyboard = Telecr::Markup.inline do |k|
    #     k.row(callback("Yes", "yes_data"), callback("No", "no_data"))
    #     k.row(url("Visit site", "https://example.com"))
    #   end
    #
    # @return [InlineKeyboard] The constructed keyboard
    def self.inline(&block : InlineBuilder ->)
      builder = InlineBuilder.new
      block.call(builder)
      builder.build
    end
  end
end