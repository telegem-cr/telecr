# memory_store.cr - In-memory session store with TTL and disk backup
# No mutex - relies on Crystal's fiber safety for basic operations

module Telecr
  module Session
    # MemoryStore stores session data in RAM with expiration
    # Features:
    # - TTL (time-to-live) for automatic expiration
    # - Automatic cleanup of expired entries
    # - Disk backup to prevent data loss
    class MemoryStore
      # Initialize the store
      # 
      # @param default_ttl [Int32] Default time-to-live in seconds (default: 300)
      # @param cleanup_interval [Int32] How often to clean expired entries (default: 300)
      # @param backup_path [String?] Path to save backup file (nil = no backup)
      # @param backup_interval [Int32] How often to save backup in seconds (default: 60)
      def initialize(
        @default_ttl : Int32 = 300,
        @cleanup_interval : Int32 = 300,
        @backup_path : String? = nil,
        @backup_interval : Int32 = 60
      )
        # Main storage hash - session_id => data
        @store = {} of String => JSON::Any
        
        # TTL tracking - when each key expires
        @ttls = {} of String => Time
        
        # Last cleanup timestamp
        @last_cleanup = Time.utc
        
        # Last backup timestamp
        @last_backup = Time.utc
        
        # Load from disk if backup exists
        load_from_disk if @backup_path && File.exists?(@backup_path)
      end
      
      # Store a value with optional TTL
      #
      # @param key [String | Int | Int64] The session identifier
      # @param value [JSON::Any] The data to store
      # @param ttl [Int32?] Time-to-live in seconds (nil = use default)
      # @return [JSON::Any] The stored value
      def set(key, value, ttl = nil)
        auto_cleanup
        key_s = key.to_s
        
        # Store the value
        @store[key_s] = value
        
        # Set expiration time
        ttl_seconds = ttl || @default_ttl
        @ttls[key_s] = Time.utc + ttl_seconds.seconds
        
        # Trigger backup if interval passed
        auto_backup
        
        value
      end
      
      # Retrieve a value by key
      #
      # @param key [String | Int | Int64] The session identifier
      # @return [JSON::Any?] The stored value or nil if not found/expired
      def get(key)
        key_s = key.to_s
        
        # Check if key exists
        return nil unless @store.has_key?(key_s)
        
        # Check if expired
        if expired?(key_s)
          delete(key_s)
          return nil
        end
        
        @store[key_s]
      end
      
      # Check if key exists and not expired
      #
      # @param key [String | Int | Int64] The session identifier
      # @return [Bool] True if exists and valid
      def exists?(key)
        key_s = key.to_s
        return false unless @store.has_key?(key_s)
        !expired?(key_s)
      end
      
      # Delete a key
      #
      # @param key [String | Int | Int64] The session identifier
      # @return [Bool] True if deleted
      def delete(key)
        key_s = key.to_s
        @store.delete(key_s)
        @ttls.delete(key_s)
        auto_backup
        true
      end
      
      # Increment a numeric value
      #
      # @param key [String | Int | Int64] The session identifier
      # @param amount [Int32] Amount to increment by
      # @param ttl [Int32?] Optional TTL for the key
      # @return [Int32] New value
      def increment(key, amount = 1, ttl = nil)
        key_s = key.to_s
        current = get(key_s)
        
        # Convert current value to integer
        new_value = case current
        when Int
          current.as(Int) + amount
        when String
          current.as_s.to_i + amount
        else
          amount
        end
        
        # Store as integer
        set(key_s, new_value.to_json.as(JSON::Any), ttl)
        new_value
      end
      
      # Decrement a numeric value
      #
      # @param key [String | Int | Int64] The session identifier
      # @param amount [Int32] Amount to decrement by
      # @return [Int32] New value
      def decrement(key, amount = 1, ttl = nil)
        increment(key, -amount, ttl)
      end
      
      # Get all non-expired keys
      #
      # @return [Array(String)] List of valid keys
      def keys
        auto_cleanup
        @store.keys.select { |k| !expired?(k) }
      end
      
      # Get number of non-expired entries
      #
      # @return [Int32] Size of store
      def size
        keys.size
      end
      
      # Check if store is empty
      #
      # @return [Bool] True if no valid entries
      def empty?
        size == 0
      end
      
      # Get remaining TTL for a key in seconds
      #
      # @param key [String | Int | Int64] The session identifier
      # @return [Int32] Seconds remaining (-1 if expired or not found)
      def ttl(key)
        key_s = key.to_s
        return -1 unless @ttls.has_key?(key_s)
        
        remaining = @ttls[key_s] - Time.utc
        remaining > 0 ? remaining.seconds.to_i : -1
      end
      
      # Set expiration for existing key
      #
      # @param key [String | Int | Int64] The session identifier
      # @param ttl [Int32] Seconds until expiration
      # @return [Bool] True if successful
      def expire(key, ttl)
        key_s = key.to_s
        return false unless @store.has_key?(key_s)
        
        @ttls[key_s] = Time.utc + ttl.seconds
        auto_backup
        true
      end
      
      # Scan for keys matching a pattern (Redis-like)
      #
      # @param pattern [String] Pattern with * and ? wildcards
      # @param count [Int32] Maximum number of keys to return
      # @return [Array(String)] Matching keys
      def scan(pattern = "*", count = 10)
        auto_cleanup
        regex = pattern_to_regex(pattern)
        matching = @store.keys.select do |k|
          k.match(regex) && !expired?(k)
        end
        matching.first(count)
      end
      
      # Clear all data (both memory and disk)
      def clear
        @store.clear
        @ttls.clear
        @last_cleanup = Time.utc
        
        # Delete backup file if exists
        if @backup_path && File.exists?(@backup_path)
          File.delete(@backup_path)
        end
      end
      
      # Force a backup to disk
      def backup!
        return unless @backup_path
        
        data = {
          store: @store,
          ttls: @ttls.map { |k, v| {k, v.to_unix} },
          timestamp: Time.utc.to_unix
        }
        
        # Create backup directory if needed
        dir = File.dirname(@backup_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)
        
        # Write to temp file then rename (atomic)
        temp_path = "#{@backup_path}.tmp"
        File.write(temp_path, data.to_json)
        File.rename(temp_path, @backup_path)
        
        @last_backup = Time.utc
      end
      
      # Restore from disk
      def restore!
        return unless @backup_path && File.exists?(@backup_path)
        
        data = JSON.parse(File.read(@backup_path))
        
        # Restore store
        @store = {} of String => JSON::Any
        data["store"].as_h.each do |k, v|
          @store[k.to_s] = v
        end
        
        # Restore TTLs
        @ttls = {} of String => Time
        data["ttls"].as_a.each do |item|
          k = item[0].to_s
          t = Time.unix(item[1].as_i64)
          @ttls[k] = t
        end
        
        puts "Restored #{@store.size} sessions from backup"
      end
      
     
      
      # Check if a key has expired
      def expired?(key)
        @ttls.has_key?(key) && Time.utc > @ttls[key]
      end
      
      # Auto-cleanup expired entries if interval passed
      def auto_cleanup
        if Time.utc - @last_cleanup > @cleanup_interval.seconds
          cleanup
        end
      end
      
      # Remove all expired entries
      def cleanup
        now = Time.utc
        @ttls.each do |key, expires|
          if now > expires
            @store.delete(key)
            @ttls.delete(key)
          end
        end
        @last_cleanup = now
      end
      
      # Auto-backup if interval passed
      def auto_backup
        if @backup_path && (Time.utc - @last_backup > @backup_interval.seconds)
          backup!
        end
      end
      
      # Convert glob pattern to regex
      def pattern_to_regex(pattern)
        regex_str = pattern.gsub("*", ".*").gsub("?", ".")
        Regex.new("^#{regex_str}$")
      end
      
      # Load from disk on startup
      def load_from_disk
        return unless @backup_path && File.exists?(@backup_path)
        
        begin
          restore!
        rescue e
          puts "Failed to load backup: #{e.message}"
        end
      end
    end
  end
end