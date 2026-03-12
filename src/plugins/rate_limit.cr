# rate_limit.cr - Rate limiting middleware for Telecr
# Prevents bots from being overwhelmed by too many requests

module Telecr
  module Plugins
    # RateLimit middleware limits requests based on:
    # - Global: overall bot usage
    # - Per-user: individual user limits
    # - Per-chat: per group/channel limits
    class RateLimit < Core::Middleware
      # Initialize with custom options
      #
      # @param options [Hash] Rate limiting configuration
      # @option options [Hash] :global {max: 30, per: 1}  Global limit
      # @option options [Hash] :user {max: 5, per: 10}    Per-user limit
      # @option options [Hash] :chat {max: 20, per: 60}   Per-chat limit
      def initialize(**options)
        @options = {
          global: {max: 30, per: 1},
          user: {max: 5, per: 10},
          chat: {max: 20, per: 60}
        }.merge(options)
        
        # Use MemoryStore for rate limiting counters
        @counters = {
          global: Session::MemoryStore.new,
          user: Session::MemoryStore.new,
          chat: Session::MemoryStore.new
        }
      end
      
      # Main middleware call
      #
      # @param ctx [Core::Context] Current context
      # @param next_mw [Proc(Core::Context ->)] Next middleware
      # @return [Any] Result from chain
      def call(ctx : Core::Context, next_mw : Core::Context ->)
        # Skip rate limiting for certain update types
        return next_mw.call(ctx) unless should_rate_limit?(ctx)
        
        # Check if limits exceeded
        if limit_exceeded?(ctx)
          ctx.logger.warn("Rate limit exceeded for #{ctx.from&.id}") if ctx.logger
          return rate_limit_response(ctx)
        end
        
        # Increment counters and continue
        increment_counters(ctx)
        next_mw.call(ctx)
      end
      
      private
      
      # Determine if this update should be rate limited
      def should_rate_limit?(ctx : Core::Context) : Bool
        # Don't rate limit polls or chat member updates
        return false if ctx.update.poll?
        return false if ctx.update.chat_member?
        true
      end
      
      # Check if any limit is exceeded
      def limit_exceeded?(ctx : Core::Context) : Bool
        global_limit?(ctx) || user_limit?(ctx) || chat_limit?(ctx)
      end
      
      # Check global limit
      def global_limit?(ctx : Core::Context) : Bool
        check_limit(:global, "global", ctx)
      end
      
      # Check per-user limit
      def user_limit?(ctx : Core::Context) : Bool
        return false unless user_id = ctx.from&.id
        check_limit(:user, "user:#{user_id}", ctx)
      end
      
      # Check per-chat limit
      def chat_limit?(ctx : Core::Context) : Bool
        return false unless chat_id = ctx.chat&.id
        check_limit(:chat, "chat:#{chat_id}", ctx)
      end
      
      # Generic limit checker
      def check_limit(type : Symbol, key : String, ctx : Core::Context) : Bool
        limit_config = @options[type]?
        return false unless limit_config
        
        counter = @counters[type].get(key)
        current = counter ? counter.to_s.to_i : 0
        current >= limit_config[:max]
      end
      
      # Increment all applicable counters
      def increment_counters(ctx : Core::Context)
        now = Time.utc
        
        # Global counter
        if global_config = @options[:global]?
          @counters[:global].increment("global", 1, ttl: global_config[:per])
        end
        
        # User counter
        if (user_config = @options[:user]?) && (user_id = ctx.from&.id)
          @counters[:user].increment("user:#{user_id}", 1, ttl: user_config[:per])
        end
        
        # Chat counter
        if (chat_config = @options[:chat]?) && (chat_id = ctx.chat&.id)
          @counters[:chat].increment("chat:#{chat_id}", 1, ttl: chat_config[:per])
        end
      end
      
      # Response when rate limit is hit
      def rate_limit_response(ctx : Core::Context)
        ctx.reply("⏳ Please wait a moment before sending another request.") rescue nil
        nil
      end
    end
  end
end