# handler.cr - Defines bot handlers and their behavior
# A handler is what runs when a matching update arrives

module Telecr
  module Core
    # Value type for filters - can be various types
    alias FilterValue = String | Int32 | Int64 | Bool | Regex | Nil

    # Handler struct - stores user's code and when to run it
    struct Handler
      # Filters determine when this handler should run
      getter filters : Hash(String, FilterValue)
      
      # The actual user code that runs
      getter proc : Context ->
      
      # How many times this handler has been   called (useful for stats)
      property call_count : Int32
      
      # Time this handler was registered
      getter created_at : Time
      
      def initialize(@filters, @proc)
        @call_count = 0
        @created_at = Time.utc
      end
      
      # Execute the handler with given context
      def call(ctx : Context)
        @call_count += 1
        @proc.call(ctx)
      end
      
      # Check if this handler should run for the given context
      def matches?(ctx : Context) : Bool
        return true if @filters.empty?
        
        @filters.all? do |key, value|
          case key
          when "text"
            matches_text?(ctx, value)
          when "chat_type"
            matches_chat_type?(ctx, value)
          when "command"
            matches_command?(ctx, value)
          when "location"
            !ctx.message.try(&.location).nil?
          when "contact"
            !ctx.message.try(&.contact).nil?
          when "web_app_data"
            !ctx.message.try(&.web_app_data).nil?
          else
            # Handle dynamic keys by checking specific known properties
            # instead of using responds_to? with dynamic symbols
            handle_dynamic_filter(ctx, key, value)
          end
        end
      end
      
      # String representation for debugging
      def to_s(io : IO) : Nil
        io << "#<Handler filters=#{@filters.keys} calls=#{@call_count}>"
      end
      
      private
      
      def matches_text?(ctx, pattern : FilterValue) : Bool
        return false unless text = ctx.message.try(&.text)
        
        case pattern
        when Regex
          text.match?(pattern)
        when String
          text.includes?(pattern)
        else
          false
        end
      end
      
      def matches_chat_type?(ctx, type : FilterValue) : Bool
        return false unless chat = ctx.chat
        chat.chat_type == type.to_s
      end
      
      def matches_command?(ctx, cmd_name : FilterValue) : Bool
        return false unless ctx.message.try(&.command?)
        ctx.message.try(&.command_name) == cmd_name.to_s
      end
      
      # Handle dynamic filter keys without using responds_to? with dynamic symbols
      def handle_dynamic_filter(ctx : Context, key : String, value : FilterValue) : Bool
        # Check common context properties
        case key
        when "message_id"
          val = ctx.message_id
          val == value if val
        when "user_id"
          val = ctx.user_id
          val == value if val
        when "chat_id"
          if chat = ctx.chat
            chat.id == value
          end
        when "update_type"
          ctx.update_type.to_s == value.to_s
        else
          # If we don't recognize the key, filter doesn't match
          false
        end
      end
    end
    
    # Collection of handlers with helper methods
    class HandlerCollection
      def initialize
        @handlers = {} of String => Array(Handler)
      end
      
      # Add a handler for a specific update type
      def add(type : String, filters : Hash(String, FilterValue), proc : Context ->)
        @handlers[type] ||= [] of Handler
        @handlers[type] << Handler.new(filters, proc)
      end
      
      # Get all handlers for a type
      def for_type(type : String) : Array(Handler)
        @handlers[type]? || [] of Handler
      end
      
      # Find first matching handler for context
      def find_match(ctx : Context) : Handler?
        type = detect_type(ctx.update)
        
        for_type(type).each do |handler|
          return handler if handler.matches?(ctx)
        end
        
        nil
      end
      
      # Remove all handlers
      def clear
        @handlers.clear
      end
      
      # Get statistics
      def stats : Hash(String, JSON::Any)
        stats = {} of String => JSON::Any
        
        @handlers.each do |type, handlers|
          stats[type] = {
            "count" => handlers.size,
            "total_calls" => handlers.sum(&.call_count)
          }.to_json.as(JSON::Any)
        end
        
        stats
      end
      
      private def detect_type(update)
        return "message" if update.message?
        return "callback_query" if update.callback_query?
        return "inline_query" if update.inline_query?
        return "chat_member" if update.chat_member?
        return "poll" if update.poll?
        return "pre_checkout_query" if update.pre_checkout_query?
        return "shipping_query" if update.shipping_query?
        return "poll_answer" if update.poll_answer?
        return "chat_join_request" if update.chat_join_request?
        return "chat_boost" if update.chat_boost?
        return "removed_chat_boost" if update.removed_chat_boost?
        return "message_reaction" if update.message_reaction?
        return "message_reaction_count" if update.message_reaction_count?
        "unknown"
      end
    end
  end
end