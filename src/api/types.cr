# types.cr - Telegram API type system for Telecr

module Telecr
  module Types
    # Base class for all Telegram API objects
    abstract class BaseType
      # Raw data from Telegram
      getter raw : Hash(String, JSON::Any)

      def initialize(@raw)
      end

      # Convert back to hash
      def to_h : Hash(String, JSON::Any)
        @raw
      end

      # Inspect for debugging
      def inspect(io : IO) : Nil
        io << "#<" << self.class.name << " " << @raw.inspect << ">"
      end

      # String representation
      def to_s(io : IO) : Nil
        inspect(io)
      end

      # Helper to convert nested objects
      protected def wrap(key : String, klass : BaseType.class) : Nil
        if value = @raw[key]?
          @raw[key] = klass.new(value.as_h).to_h.as(JSON::Any) unless value.is_a?(BaseType)
        end
      end

      # Helper to convert nested arrays
      protected def wrap_array(key : String, klass : BaseType.class) : Nil
        if arr = @raw[key]?.try(&.as_a?)
          @raw[key] = arr.map do |item|
            if item.is_a?(BaseType)
              item.to_h.as(JSON::Any)
            else
              klass.new(item.as_h).to_h.as(JSON::Any)
            end
          end.as(JSON::Any)
        end
      end

      # Convert snake_case to camelCase
      protected def snake_to_camel(str : String) : String
        str.gsub(/_([a-z])/) { $1.upcase }
      end

      # Convert camelCase to snake_case
      protected def camel_to_snake(str : String) : String
        str.gsub(/([A-Z])/) { "_#{$1.downcase}" }.lstrip('_')
      end
    end

    # User object
    class User < BaseType
      def id : Int64?
        @raw["id"]?.try(&.as_i64)
      end

      def is_bot : Bool?
        @raw["is_bot"]?.try(&.as_bool)
      end

      def first_name : String?
        @raw["first_name"]?.try(&.as_s)
      end

      def last_name : String?
        @raw["last_name"]?.try(&.as_s)
      end

      def username : String?
        @raw["username"]?.try(&.as_s)
      end

      def language_code : String?
        @raw["language_code"]?.try(&.as_s)
      end

      def is_premium : Bool?
        @raw["is_premium"]?.try(&.as_bool)
      end

      def full_name : String
        [first_name, last_name].compact.join(" ")
      end

      def mention : String
        if username = self.username
          "@#{username}"
        elsif first_name = self.first_name
          first_name
        else
          "User ##{id}"
        end
      end

      def to_s : String
        full_name
      end
    end

    # Chat object
    class Chat < BaseType
      def id : Int64?
        @raw["id"]?.try(&.as_i64)
      end

      def chat_type : String?
        @raw["type"]?.try(&.as_s)
      end

      def title : String?
        @raw["title"]?.try(&.as_s)
      end

      def username : String?
        @raw["username"]?.try(&.as_s)
      end

      def first_name : String?
        @raw["first_name"]?.try(&.as_s)
      end

      def last_name : String?
        @raw["last_name"]?.try(&.as_s)
      end

      def private? : Bool
        chat_type == "private"
      end

      def group? : Bool
        chat_type == "group"
      end

      def supergroup? : Bool
        chat_type == "supergroup"
      end

      def channel? : Bool
        chat_type == "channel"
      end

      def to_s : String
        title || username || "Chat ##{id}"
      end
    end

    # Message entity object
    class MessageEntity < BaseType
      def entity_type : String?
        @raw["type"]?.try(&.as_s)
      end

      def offset : Int32?
        @raw["offset"]?.try(&.as_i)
      end

      def length : Int32?
        @raw["length"]?.try(&.as_i)
      end

      def url : String?
        @raw["url"]?.try(&.as_s)
      end

      def user : User?
        if user_data = @raw["user"]?
          User.new(user_data.as_h)
        end
      end

      def language : String?
        @raw["language"]?.try(&.as_s)
      end
    end

    # Message object
    class Message < BaseType
      def message_id : Int64?
        @raw["message_id"]?.try(&.as_i64)
      end

      def from : User?
        if user_data = @raw["from"]?
          User.new(user_data.as_h)
        end
      end

      def chat : Chat?
        if chat_data = @raw["chat"]?
          Chat.new(chat_data.as_h)
        end
      end

      def date : Time?
        if timestamp = @raw["date"]?.try(&.as_i)
          Time.unix(timestamp)
        end
      end

      def text : String?
        @raw["text"]?.try(&.as_s)
      end

      def caption : String?
        @raw["caption"]?.try(&.as_s)
      end

      def entities : Array(MessageEntity)
        if entities_data = @raw["entities"]?.try(&.as_a)
          entities_data.map { |e| MessageEntity.new(e.as_h) }
        else
          [] of MessageEntity
        end
      end

      def caption_entities : Array(MessageEntity)
        if entities_data = @raw["caption_entities"]?.try(&.as_a)
          entities_data.map { |e| MessageEntity.new(e.as_h) }
        else
          [] of MessageEntity
        end
      end

      def reply_to_message : Message?
        if msg_data = @raw["reply_to_message"]?
          Message.new(msg_data.as_h)
        end
      end

      def via_bot : User?
        if user_data = @raw["via_bot"]?
          User.new(user_data.as_h)
        end
      end

      def command? : Bool
        return false unless text = self.text
        return false unless entities = @raw["entities"]?.try(&.as_a)

        entities.any? do |e|
          e["type"] == "bot_command" &&
            text[e["offset"].as_i, e["length"].as_i]?.try(&.starts_with?('/'))
        end
      end

      def command_name : String?
        return nil unless command?
        return nil unless text = self.text
        return nil unless entities = @raw["entities"]?.try(&.as_a)

        cmd_entity = entities.find { |e| e["type"] == "bot_command" }
        return nil unless cmd_entity

        offset = cmd_entity["offset"].as_i
        length = cmd_entity["length"].as_i
        cmd = text[offset, length]

        return nil if cmd.size <= 1

        cmd = cmd[1..-1]
        cmd.split('@').first.strip
      end

      def command_args : String?
        return nil unless command?
        return nil unless text = self.text
        return nil unless entities = @raw["entities"]?.try(&.as_a)

        cmd_entity = entities.find { |e| e["type"] == "bot_command" }
        return nil unless cmd_entity

        offset = cmd_entity["offset"].as_i
        length = cmd_entity["length"].as_i

        args_start = offset + length
        return nil if args_start >= text.size

        next_entity = entities
          .select { |e| e["offset"].as_i >= args_start }
          .min_by? { |e| e["offset"].as_i }

        if next_entity
          args_end = next_entity["offset"].as_i - 1
          text[args_start..args_end]?.try(&.strip)
        else
          text[args_start..-1]?.try(&.strip)
        end
      end

      def reply? : Bool
        !!@raw["reply_to_message"]?
      end

      def has_media? : Bool
        !!(audio? || document? || photo? || video? || voice? || video_note? || sticker?)
      end

      def media_type : Symbol?
        return :audio if audio?
        return :document if document?
        return :photo if photo?
        return :video if video?
        return :voice if voice?
        return :video_note if video_note?
        return :sticker if sticker?
        nil
      end

      def audio? : Bool
        !!@raw["audio"]?
      end

      def document? : Bool
        !!@raw["document"]?
      end

      def photo? : Bool
        !!@raw["photo"]?
      end

      def video? : Bool
        !!@raw["video"]?
      end

      def voice? : Bool
        !!@raw["voice"]?
      end

      def video_note? : Bool
        !!@raw["video_note"]?
      end

      def sticker? : Bool
        !!@raw["sticker"]?
      end
    end

    # Callback query object
    class CallbackQuery < BaseType
      def id : String?
        @raw["id"]?.try(&.as_s)
      end

      def from : User?
        if user_data = @raw["from"]?
          User.new(user_data.as_h)
        end
      end

      def message : Message?
        if msg_data = @raw["message"]?
          Message.new(msg_data.as_h)
        end
      end

      def inline_message_id : String?
        @raw["inline_message_id"]?.try(&.as_s)
      end

      def chat_instance : String?
        @raw["chat_instance"]?.try(&.as_s)
      end

      def data : String?
        @raw["data"]?.try(&.as_s)
      end

      def game_short_name : String?
        @raw["game_short_name"]?.try(&.as_s)
      end

      def from_user? : Bool
        !!@raw["from"]?
      end

      def message? : Bool
        !!@raw["message"]?
      end

      def inline_message? : Bool
        !!@raw["inline_message_id"]?
      end
    end

    # Update object (root of all incoming data)
    class Update < BaseType
      def update_id : Int64?
        @raw["update_id"]?.try(&.as_i64)
      end

      def message : Message?
        if msg_data = @raw["message"]?
          Message.new(msg_data.as_h)
        end
      end

      def edited_message : Message?
        if msg_data = @raw["edited_message"]?
          Message.new(msg_data.as_h)
        end
      end

      def channel_post : Message?
        if msg_data = @raw["channel_post"]?
          Message.new(msg_data.as_h)
        end
      end

      def edited_channel_post : Message?
        if msg_data = @raw["edited_channel_post"]?
          Message.new(msg_data.as_h)
        end
      end

      def inline_query : InlineQuery?
        if data = @raw["inline_query"]?
          InlineQuery.new(data.as_h)
        end
      end

      def chosen_inline_result : ChosenInlineResult?
        if data = @raw["chosen_inline_result"]?
          ChosenInlineResult.new(data.as_h)
        end
      end

      def callback_query : CallbackQuery?
        if data = @raw["callback_query"]?
          CallbackQuery.new(data.as_h)
        end
      end

      def shipping_query : ShippingQuery?
        if data = @raw["shipping_query"]?
          ShippingQuery.new(data.as_h)
        end
      end

      def pre_checkout_query : PreCheckoutQuery?
        if data = @raw["pre_checkout_query"]?
          PreCheckoutQuery.new(data.as_h)
        end
      end

      def poll : Poll?
        if data = @raw["poll"]?
          Poll.new(data.as_h)
        end
      end

      def poll_answer : PollAnswer?
        if data = @raw["poll_answer"]?
          PollAnswer.new(data.as_h)
        end
      end

      def my_chat_member : ChatMemberUpdated?
        if data = @raw["my_chat_member"]?
          ChatMemberUpdated.new(data.as_h)
        end
      end

      def chat_member : ChatMemberUpdated?
        if data = @raw["chat_member"]?
          ChatMemberUpdated.new(data.as_h)
        end
      end

      def chat_join_request : ChatJoinRequest?
        if data = @raw["chat_join_request"]?
          ChatJoinRequest.new(data.as_h)
        end
      end

      def update_type : Symbol
        return :message if message?
        return :edited_message if edited_message?
        return :channel_post if channel_post?
        return :edited_channel_post if edited_channel_post?
        return :inline_query if inline_query?
        return :chosen_inline_result if chosen_inline_result?
        return :callback_query if callback_query?
        return :shipping_query if shipping_query?
        return :pre_checkout_query if pre_checkout_query?
        return :poll if poll?
        return :poll_answer if poll_answer?
        return :my_chat_member if my_chat_member?
        return :chat_member if chat_member?
        return :chat_join_request if chat_join_request?
        :unknown
      end

      def from : User?
        case
        when msg = message          then msg.from
        when msg = edited_message   then msg.from
        when msg = channel_post     then msg.from
        when msg = edited_channel_post then msg.from
        when iq = inline_query      then iq.from
        when cir = chosen_inline_result then cir.from
        when cq = callback_query    then cq.from
        when sq = shipping_query    then sq.from
        when pcq = pre_checkout_query then pcq.from
        when cmu = my_chat_member   then cmu.from
        when cmu = chat_member      then cmu.from
        when cjr = chat_join_request then cjr.from
        else nil
        end
      end

      def message? : Bool
        !!@raw["message"]?
      end

      def edited_message? : Bool
        !!@raw["edited_message"]?
      end

      def channel_post? : Bool
        !!@raw["channel_post"]?
      end

      def edited_channel_post? : Bool
        !!@raw["edited_channel_post"]?
      end

      def inline_query? : Bool
        !!@raw["inline_query"]?
      end

      def chosen_inline_result? : Bool
        !!@raw["chosen_inline_result"]?
      end

      def callback_query? : Bool
        !!@raw["callback_query"]?
      end

      def shipping_query? : Bool
        !!@raw["shipping_query"]?
      end

      def pre_checkout_query? : Bool
        !!@raw["pre_checkout_query"]?
      end

      def poll? : Bool
        !!@raw["poll"]?
      end

      def poll_answer? : Bool
        !!@raw["poll_answer"]?
      end

      def my_chat_member? : Bool
        !!@raw["my_chat_member"]?
      end

      def chat_member? : Bool
        !!@raw["chat_member"]?
      end

      def chat_join_request? : Bool
        !!@raw["chat_join_request"]?
      end
    end

    class InlineQuery < BaseType
      def from : User?
        if data = @raw["from"]?
          User.new(data.as_h)
        end
      end
    end

    class ChosenInlineResult < BaseType
      def from : User?
        if data = @raw["from"]?
          User.new(data.as_h)
        end
      end
    end

    class ShippingQuery < BaseType
      def from : User?
        if data = @raw["from"]?
          User.new(data.as_h)
        end
      end
    end

    class PreCheckoutQuery < BaseType
      def from : User?
        if data = @raw["from"]?
          User.new(data.as_h)
        end
      end
    end

    class Poll < BaseType; end
    class PollAnswer < BaseType; end
    
    class ChatMemberUpdated < BaseType
      def from : User?
        if data = @raw["from"]?
          User.new(data.as_h)
        end
      end
    end

    class ChatJoinRequest < BaseType
      def from : User?
        if data = @raw["from"]?
          User.new(data.as_h)
        end
      end
    end
  end
end