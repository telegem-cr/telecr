# context.cr - Context object passed through middleware and handlers
# Contains all data about the current update and provides helper methods
# Fully compatible with Telegram Bot API 9.5 (March 2026)
# Note: Uses explicit conditionals instead of &. to avoid compiler issues

module Telecr
  module Core 
    # Context holds everything related to a single Telegram update
    # It's passed through middleware chain and finally to the user's handler
    class Context
      # Core properties
      property update : Types::Update      # The raw update from Telegram
      property bot : Bot                    # The bot instance handling this update
      property state : Hash(Symbol, JSON::Any)  # Shared state between middlewares
      property match : Regex::MatchData?    # Match data from pattern matching (command/hears)
      property session : Hash(String, JSON::Any)  # Session data for this user
      property typing_active : Bool = false  # Track if typing indicator is active
      
      # Initialize with update and bot
      def initialize(@update : Types::Update, @bot : Bot)
        @state = {} of Symbol => JSON::Any
        @session = {} of String => JSON::Any
        @match = nil
        @typing_active = false
      end 
      
      # ===== Update Type Accessors =====
      
      # Get the message if this update is a message
      def message : Types::Message?
        @update.message
      end 
      
      # Get the callback query if this update is a callback
      def callback_query : Types::CallbackQuery?
        @update.callback_query
      end 
      
      # Get the inline query if this update is an inline query
      def inline_query : Types::InlineQuery?
        @update.inline_query
      end 
      
      # Get the user who sent this update
      def from : Types::User?
        if msg = self.message
          msg.from
        elsif cq = self.callback_query
          cq.from
        elsif iq = self.inline_query
          iq.from
        else
          nil
        end
      end 
      
      # Get the chat where this update occurred
      def chat : Types::Chat?
        if msg = self.message
          msg.chat
        elsif cq = self.callback_query
          if cq_msg = cq.message
            cq_msg.chat
          end
        end
      end 
      
      # Get callback data (for callback queries)
      def data : String?
        if cq = self.callback_query
          cq.data
        end
      end 
      
      # Get inline query text
      def query : String?
        if iq = self.inline_query
          iq.query
        end
      end 
      
      # ===== Message Properties =====
      
      # Get message ID
      def message_id : Int64?
        if msg = self.message
          msg.message_id
        end
      end 
      
      # Get message date
      def message_date : Time?
        if msg = self.message
          msg.date
        end
      end 
      
      # Get edit date if message was edited
      def edit_date : Time?
        if msg = self.message
          msg.edit_date
        end
      end 
      
      # Get command name if this is a command
      def command_name : String?
        if msg = self.message
          msg.command_name
        end
      end 
      
      # Check if message has media
      def has_media? : Bool
        if msg = self.message
          msg.has_media?
        else
          false
        end
      end 
      
      # Get media type if present
      def media_type : Symbol?
        if msg = self.message
          msg.media_type
        end
      end 
      
      # Get message entities
      def entities : Array(Types::MessageEntity)
        if msg = self.message
          msg.entities
        else
          [] of Types::MessageEntity
        end
      end 
      
      # Get caption entities
      def caption_entities : Array(Types::MessageEntity)
        if msg = self.message
          msg.caption_entities
        else
          [] of Types::MessageEntity
        end
      end 
      
      # Get message caption
      def caption : String?
        if msg = self.message
          msg.caption
        end
      end 

      # Check if this is a reply to another message
      def reply? : Bool
        if msg = self.message
          msg.reply?
        else
          false
        end
      end 

      # Get the message being replied to
      def replied_message : Types::Message?
        if msg = self.message
          msg.reply_to_message
        end
      end 

      # Get text of replied message
      def replied_text : String?
        if reply_msg = self.replied_message
          reply_msg.text
        end
      end 

      # Get sender of replied message
      def replied_from : Types::User?
        if reply_msg = self.replied_message
          reply_msg.from
        end
      end 

      # Get chat of replied message
      def replied_chat : Types::Chat?
        if reply_msg = self.replied_message
          reply_msg.chat
        end
      end 

      # NEW in API 9.5: Get sender tag (for group members)
      def sender_tag : String?
        if msg = self.message
          msg.sender_tag
        end
      end
      
      # ===== Update Type Detection =====
      
      # Get the type of this update as a symbol
      def update_type : Symbol
        @update.update_type
      end 

      # Check if this is an edited message
      def edited? : Bool
        !!@update.edited_message
      end 

      # Check if this is a channel post
      def channel_post? : Bool
        self.update_type == :channel_post
      end 

      # Check if this is a callback query
      def callback_query? : Bool
        self.update_type == :callback_query
      end 

      # Check if this is an inline query
      def inline_query? : Bool
        self.update_type == :inline_query
      end 
      
      # Check if this is a command message
      def command? : Bool
        if msg = self.message
          msg.command?
        else
          false
        end
      end
      
      # Get command arguments if this is a command
      def command_args : String?
        if self.command?
          if msg = self.message
            msg.command_args
          end
        end
      end
      
      # ===== Response Methods =====
      
      # Send a text message to the chat
      def reply(text : String, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, text: text }.merge(options)
          @bot.client.call("sendMessage", params)
        end
      end
      
      # NEW in API 9.5: Send a message draft (streaming)
      def reply_draft(text : String, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, text: text }.merge(options)
          @bot.client.call("sendMessageDraft", params)
        end
      end
      
      # Edit the current message text
      def edit_message_text(text : String, **options)
        if (msg = self.message) && (chat_obj = self.chat)
          params = {
            chat_id: chat_obj.id,
            message_id: msg.message_id,
            text: text
          }.merge(options)
          
          @bot.client.call("editMessageText", params)
        end
      end
      
      # Delete a message
      def delete_message(message_id : Int64? = nil)
        mid = message_id || (self.message ? self.message.message_id : nil)
        if mid && (chat_obj = self.chat)
          @bot.client.call("deleteMessage", {chat_id: chat_obj.id, message_id: mid})
        end
      end
      
      # Answer a callback query
      def answer_callback_query(text : String? = nil, show_alert : Bool = false, **options)
        if cq = self.callback_query
          params = {
            callback_query_id: cq.id,
            show_alert: show_alert
          }.merge(options)
          
          params[:text] = text if text
          @bot.client.call("answerCallbackQuery", params)
        end
      end
      
      # Answer an inline query with results
      def answer_inline_query(results : Array, **options)
        if iq = self.inline_query
          params = {
            inline_query_id: iq.id,
            results: results.to_json
          }.merge(options)
          
          @bot.client.call("answerInlineQuery", params)
        end
      end
      
      # ===== Media Sending Methods =====
      
      # Send a photo
      def photo(photo, caption : String? = nil, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, caption: caption }.merge(options)
          
          if file_object?(photo)
            @bot.client.upload("sendPhoto", params.merge(photo: photo))
          else
            @bot.client.call("sendPhoto", params.merge(photo: photo))
          end
        end
      end
      
      # Send a document
      def document(document, caption : String? = nil, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, caption: caption }.merge(options)
          
          if file_object?(document)
            @bot.client.upload("sendDocument", params.merge(document: document))
          else
            @bot.client.call("sendDocument", params.merge(document: document))
          end
        end
      end
      
      # Send an audio file
      def audio(audio, caption : String? = nil, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, caption: caption }.merge(options)
          
          if file_object?(audio)
            @bot.client.upload("sendAudio", params.merge(audio: audio))
          else
            @bot.client.call("sendAudio", params.merge(audio: audio))
          end
        end
      end
      
      # Send a video
      def video(video, caption : String? = nil, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, caption: caption }.merge(options)
          
          if file_object?(video)
            @bot.client.upload("sendVideo", params.merge(video: video))
          else
            @bot.client.call("sendVideo", params.merge(video: video))
          end
        end
      end
      
      # Send a voice message
      def voice(voice, caption : String? = nil, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, caption: caption }.merge(options)
          
          if file_object?(voice)
            @bot.client.upload("sendVoice", params.merge(voice: voice))
          else
            @bot.client.call("sendVoice", params.merge(voice: voice))
          end
        end
      end
      
      # Download a file from Telegram
      def download_file(file_id : String, destination_path : String? = nil)
        @bot.client.download(file_id, destination_path) 
      end 
      
      # Send a sticker
      def sticker(sticker, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, sticker: sticker }.merge(options)
          @bot.client.call("sendSticker", params)
        end
      end
      
      # Send a location
      def location(latitude : Float64, longitude : Float64, **options)
        if chat_obj = self.chat
          params = { 
            chat_id: chat_obj.id, 
            latitude: latitude, 
            longitude: longitude 
          }.merge(options)
          
          @bot.client.call("sendLocation", params)
        end
      end
      
      # Send a chat action (typing, uploading, etc.)
      def send_chat_action(action : String, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, action: action }.merge(options)
          @bot.client.call("sendChatAction", params)
        end
      end
      
      # Forward a message from another chat
      def forward_message(from_chat_id : Int64, message_id : Int64, **options)
        if chat_obj = self.chat
          params = { 
            chat_id: chat_obj.id, 
            from_chat_id: from_chat_id, 
            message_id: message_id 
          }.merge(options)
          
          @bot.client.call("forwardMessage", params)
        end
      end
      
      # Copy a message from another chat
      def copy_message(from_chat_id : Int64, message_id : Int64, **options)
        if chat_obj = self.chat
          params = { 
            chat_id: chat_obj.id, 
            from_chat_id: from_chat_id, 
            message_id: message_id 
          }.merge(options)
          
          @bot.client.call("copyMessage", params)
        end
      end
      
      # ===== Chat Management =====
      
      # Pin a message in the chat
      def pin_message(message_id : Int64, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, message_id: message_id }.merge(options)
          @bot.client.call("pinChatMessage", params)
        end
      end
      
      # Unpin a message
      def unpin_message(**options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id }.merge(options)
          @bot.client.call("unpinChatMessage", params)
        end
      end
      
      # Kick a member from the chat
      def kick_chat_member(user_id : Int64, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, user_id: user_id }.merge(options)
          @bot.client.call("kickChatMember", params)
        end
      end
      
      # Ban a member from the chat
      def ban_chat_member(user_id : Int64, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, user_id: user_id }.merge(options)
          @bot.client.call("banChatMember", params)
        end
      end
      
      # Unban a member
      def unban_chat_member(user_id : Int64, **options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id, user_id: user_id }.merge(options)
          @bot.client.call("unbanChatMember", params)
        end
      end
      
      # Get chat administrators
      def get_chat_administrators(**options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id }.merge(options)
          @bot.client.call("getChatAdministrators", params)
        end
      end
      
      # Get members count
      def get_chat_members_count(**options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id }.merge(options)
          @bot.client.call("getChatMembersCount", params)
        end
      end
      
      # Get chat info
      def get_chat(**options)
        if chat_obj = self.chat
          params = { chat_id: chat_obj.id }.merge(options)
          @bot.client.call("getChat", params)
        end
      end
      
      # ===== Keyboard Helpers =====
      
      # Create a reply keyboard
      def keyboard(&block)
        # This would delegate to a Markup helper class
        # For now, placeholder
        {} of String => JSON::Any
      end
      
      # Create an inline keyboard
      def inline_keyboard(&block)
        # Placeholder
        {} of String => JSON::Any
      end
      
      # Reply with a keyboard
      def reply_with_keyboard(text : String, keyboard_markup, **options)
        if chat_obj = self.chat
          reply_markup = keyboard_markup.is_a?(Hash) ? keyboard_markup : keyboard_markup.to_h
          self.reply(text, reply_markup: reply_markup, **options)
        end
      end
      
      # Reply with inline keyboard
      def reply_with_inline_keyboard(text : String, inline_markup, **options)
        if chat_obj = self.chat
          reply_markup = inline_markup.is_a?(Hash) ? inline_markup : inline_markup.to_h
          self.reply(text, reply_markup: reply_markup, **options)
        end
      end
      
      # Remove keyboard
      def remove_keyboard(text : String? = nil, **options)
        if chat_obj = self.chat
          # Placeholder for keyboard removal
          reply_markup = {remove_keyboard: true}
          if text
            self.reply(text, reply_markup: reply_markup, **options)
          else
            reply_markup
          end
        end
      end
      
      # Edit message reply markup
      def edit_message_reply_markup(reply_markup, **options)
        if (msg = self.message) && (chat_obj = self.chat)
          params = {
            chat_id: chat_obj.id,
            message_id: msg.message_id,
            reply_markup: reply_markup
          }.merge(options)
          
          @bot.client.call("editMessageReplyMarkup", params)
        end
      end
      
      # ===== Chat Actions =====
      
      # Send typing action
      def typing(**options)
        self.send_chat_action("typing", **options)
      end
      
      # Send uploading photo action
      def uploading_photo(**options)
        self.send_chat_action("upload_photo", **options)
      end
      
      # Send uploading video action
      def uploading_video(**options)
        self.send_chat_action("upload_video", **options)
      end
      
      # Send uploading audio action
      def uploading_audio(**options)
        self.send_chat_action("upload_audio", **options)
      end
      
      # Send uploading document action
      def uploading_document(**options)
        self.send_chat_action("upload_document", **options)
      end
      
      # Keep typing active during a long operation
      def with_typing(&block)
        @typing_active = true
        
        # Spawn a fiber to send typing every 5 seconds
        spawn do
          while @typing_active
            self.typing
            sleep 5
          end
        end
        
        result = block.call
        @typing_active = false
        result
      end
      
      # ===== Utility Methods =====
      
      # Get logger from bot
      def logger
        @bot.logger
      end
      
      # Get raw update data (for debugging)
      def raw_update
        @update.raw
      end
      
      # Get API client
      def api
        @bot.client
      end
      
      # Get user ID
      def user_id : Int64?
        if from_obj = self.from
          from_obj.id
        end
      end
      
      # Check if object is a file (for uploads)
      private def file_object?(obj) : Bool
        obj.is_a?(File) || 
        obj.is_a?(IO) || 
        (obj.is_a?(String) && File.exists?(obj))
      end
    end
  end
end