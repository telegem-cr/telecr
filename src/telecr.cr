# telecr.cr - Main entry point for Telecr
# Require this file to use the library

require "./core/*"
require "./api/*"
require "./markup/*"
require "./plugins/*"
require "./session/*"
require "./webhook/*"
require "logger"
require "json"

module Telecr
  # Library version
  VERSION = "0.1.0"

  # Create a new bot instance
  #
  # @param token [String] Telegram bot token
  # @return [Core::Bot] Bot instance
  def self.new(token : String)
    Core::Bot.new(token)
  end
  
  # Create a reply keyboard
  #
  # @yield [Markup::ReplyBuilder] Keyboard builder
  # @return [Markup::ReplyKeyboard] Keyboard markup
  def self.keyboard(&block : Markup::ReplyBuilder ->)
    Markup.keyboard(&block)
  end
  
  # Create an inline keyboard
  #
  # @yield [Markup::InlineBuilder] Keyboard builder
  # @return [Markup::InlineKeyboard] Keyboard markup
  def self.inline(&block : Markup::InlineBuilder ->)
    Markup.inline(&block)
  end
  
  # Create remove keyboard markup
  #
  # @param options [Hash] Keyboard options
  # @return [Hash] Remove keyboard markup
  def self.remove_keyboard(**options)
    {remove_keyboard: true}.merge(options)
  end
  
  # Create force reply markup
  #
  # @param options [Hash] Force reply options
  # @return [Hash] Force reply markup
  def self.force_reply(**options)
    {force_reply: true}.merge(options)
  end
  
  # Get library version
  #
  # @return [String] Version number
  def self.version
    VERSION
  end

  # Set up webhook for bot (convenience method)
  #
  # @param bot [Core::Bot] Bot instance
  # @param options [Hash] Webhook options
  # @return [Webhook::Server] Webhook server
  def self.webhook(bot : Core::Bot, **options)
    Webhook::Server.new(bot, **options)
  end
end