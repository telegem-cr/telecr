
# Telecr

Telegram bot framework for Crystal. Inspired by telegem (Ruby).

## Installation

Add to your `shard.yml`:

```yaml
dependencies:
  telecr:
    github: telegem-cr/telecr
    version: ~> 0.1.0
```

Then run:

```bash
shards install
```

Quick Start

```crystal
require "telecr"

bot = Telecr.new("YOUR_BOT_TOKEN")

bot.command("start") do |ctx|
  ctx.reply("Welcome to Telecr!")
end

bot.start_polling
```

Features

- Full Telegram Bot API support
- Polling and webhook modes
- Middleware system (session, rate limiting, file upload)
- Reply and inline keyboards
- Type-safe context objects
- Session management with disk backup
- File upload to shrine storage

Usage

Basic Bot

```crystal
bot = Telecr.new("TOKEN")

bot.command("start") do |ctx|
  ctx.reply("Hello! I'm a Telecr bot.")
end

bot.hears(/hi/i) do |ctx|
  ctx.reply("Hi there!")
end

bot.start_polling
```

Commands with Arguments

```crystal
bot.command("echo") do |ctx|
  args = ctx.command_args
  if args && !args.empty?
    ctx.reply(args)
  else
    ctx.reply("Usage: /echo <text>")
  end
end
```

Callback Queries

```crystal
bot.command("menu") do |ctx|
  keyboard = Telecr.inline do |k|
    k.row(
      k.callback("Option 1", "opt1"),
      k.callback("Option 2", "opt2")
    )
  end
  ctx.reply("Choose:", reply_markup: keyboard.to_h)
end

bot.on(:callback_query) do |ctx|
  data = ctx.data
  case data
  when "opt1"
    ctx.answer_callback_query(text: "You chose option 1")
  when "opt2"
    ctx.answer_callback_query(text: "You chose option 2")
  end
end
```

Reply Keyboards

```crystal
keyboard = Telecr.keyboard do |k|
  k.row(
    k.text("Yes"),
    k.text("No")
  )
  k.row(
    k.request_location("Send Location")
  )
  k.resize.one_time
end

ctx.reply("Choose:", reply_markup: keyboard.to_h)
```

Inline Keyboards

```crystal
keyboard = Telecr.inline do |k|
  k.row(
    k.url("GitHub", "https://github.com"),
    k.url("Docs", "https://docs.example.com")
  )
  k.row(
    k.callback("Refresh", "refresh")
  )
end
```

Sending Media

```crystal
# Send photo
ctx.photo("path/to/photo.jpg", caption: "Nice photo!")

# Send document
ctx.document("path/to/file.pdf", caption: "Important document")

# Send location
ctx.location(37.7749, -122.4194)

# Send chat action (typing indicator)
ctx.typing
```

Downloading Files

```crystal
# Download file from Telegram
file_path = ctx.download_file(file_id, "downloads/file.jpg")

# Or get file content without saving
content = ctx.download_file(file_id)
```

Middleware

Session Middleware

```crystal
require "telecr/session"

bot.use(Telecr::Session::Middleware.new)

bot.command("count") do |ctx|
  ctx.session["count"] = (ctx.session["count"]? || 0).as_i + 1
  ctx.reply("Count: #{ctx.session["count"]}")
end
```

Rate Limit Middleware

```crystal
require "telecr/plugins/rate_limit"

bot.use(Telecr::Plugins::RateLimit.new(
  user: {max: 5, per: 10},
  chat: {max: 20, per: 60}
))
```

File Upload Plugin

```crystal
require "telecr/plugins/upload"

shrine = Shrine.new
shrine.storage = Shrine::Storage::SQLite.new("files.db")

bot.use(Telecr::Plugins::Upload.new(
  shrine: shrine,
  auto_download: true
))

bot.on_message do |ctx|
  if file = ctx.state[:uploaded_file]?
    ctx.reply("File saved: #{file.url}")
  end
end
```

Custom Middleware

```crystal
class LoggerMiddleware < Telecr::Core::Middleware
  def call(ctx, next_mw)
    start = Time.monotonic
    result = next_mw.call(ctx)
    duration = Time.monotonic - start
    ctx.logger.info("Processed in #{duration.total_milliseconds.round(2)}ms")
    result
  end
end

bot.use(LoggerMiddleware.new)
```

Webhook Mode

Local Development with SSL

```bash
# Generate SSL certificate
crystal bin/telecr-ssl.cr your-domain.com
```

```crystal
bot = Telecr.new("TOKEN")

bot.command("start") do |ctx|
  ctx.reply("Webhook bot running!")
end

bot.start_webhook(
  path: "/webhook",
  port: 8443,
  ssl: true  # Uses .telecr-ssl config file
)
```

Cloud Deployment (Heroku, Render, Railway)

```crystal
bot.start_webhook(
  path: "/webhook",
  port: ENV["PORT"].to_i,
  ssl: :cloud  # SSL handled by platform
)
```

Error Handling

```crystal
bot.error do |error, ctx|
  logger.error("Error: #{error.message}")
  ctx.reply("Something went wrong. Please try again.") if ctx
end
```

Graceful Shutdown

```crystal
Signal::INT.trap do
  bot.shutdown
  exit
end
```

Configuration

Environment Variables

| Variable | Purpose |
| ---- | --- |
| TELECR_WEBHOOK_URL |Public URL for webhooks|
| PORT | Port for webhook server |


Development

```bash
git clone https://github.com/telegem-cr/telecr
cd telecr
shards install
crystal spec
```

License

MIT

Contributors

- [ slick_phantom]()