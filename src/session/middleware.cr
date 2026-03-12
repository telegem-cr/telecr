module Telecr
  module Session
    class Middleware < Core::Middleware
      def initialize(store = nil)
        @store = store || MemoryStore.new
      end 
      
      def call(ctx, next_middleware)
        user_id = get_user_id(ctx)
        return next_middleware.call(ctx) unless user_id

        # Load session
        ctx.session = @store.get(user_id) || {}
        
        begin
          # Execute the rest of the chain
          result = next_middleware.call(ctx)
        ensure
          # Always save session, even if error
          @store.set(user_id, ctx.session)
        end
        
        result
      end
      
      private
      
      def get_user_id(ctx)
        ctx.from&.id
      end
    end
  end
end