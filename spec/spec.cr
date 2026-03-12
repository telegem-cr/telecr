# spec/telecr_spec.cr - Main spec file for Telecr

require "./spec_helper"

describe Telecr do
  it "has a version number" do
    Telecr::VERSION.should_not be_nil
    Telecr::VERSION.should be_a(String)
  end

  it "creates a new bot instance" do
    bot = Telecr.new("TEST_TOKEN")
    bot.should be_a(Telecr::Core::Bot)
    bot.client.should be_a(Telecr::Api::Client)
  end

  describe "keyboard helpers" do
    it "creates reply keyboard" do
      keyboard = Telecr.keyboard do |k|
        k.row(
          k.text("Yes"),
          k.text("No")
        )
        k.row(
          k.request_location("Send location")
        )
      end

      keyboard.should be_a(Telecr::Markup::ReplyKeyboard)
      hash = keyboard.to_h
      hash["keyboard"].should be_a(Array)
      hash["keyboard"].as_a.size.should eq(2)
    end

    it "creates inline keyboard" do
      keyboard = Telecr.inline do |k|
        k.row(
          k.callback("Option 1", "opt1"),
          k.callback("Option 2", "opt2")
        )
        k.row(
          k.url("GitHub", "https://github.com")
        )
      end

      keyboard.should be_a(Telecr::Markup::InlineKeyboard)
      hash = keyboard.to_h
      hash["inline_keyboard"].should be_a(Array)
      hash["inline_keyboard"].as_a.size.should eq(2)
    end

    it "creates remove keyboard markup" do
      markup = Telecr.remove_keyboard(selective: true)
      markup.should eq({remove_keyboard: true, selective: true})
    end

    it "creates force reply markup" do
      markup = Telecr.force_reply(selective: true)
      markup.should eq({force_reply: true, selective: true})
    end
  end
end
