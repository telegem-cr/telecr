# core/middleware.cr - Base class for all middleware

module Telecr
  module Core
    # Abstract base class that all middleware must inherit from
    abstract class Middleware
      # Every middleware must implement this method
      #
      # @param ctx [Context] The current context
      # @param next_mw [Proc(Context ->)] The next middleware in chain
      # @return [Any] Result from the rest of the chain
      abstract def call(ctx : Context, next_mw : Context ->)
    end
  end
end