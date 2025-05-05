require "sqlite3"
require "json"

module Data
  class Metadata < Base
    # Get a metadata value by key
    def get(key : String) : String?
      with_db do |db|
        db.query_one?("SELECT value FROM metadata WHERE key = ?", key) do |rs|
          rs.read(String)
        end
      end
    end

    # Add or update a metadata value
    def add(key : String, value : String) : Nil
      with_db do |db|
        db.exec("INSERT INTO metadata (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value", key, value)
      end
    end

    # List all metadata
    def list : Hash(String, String)
      result = {} of String => String

      with_db do |db|
        db.query("SELECT key, value FROM metadata ORDER BY key") do |rs|
          rs.each do
            key = rs.read(String)
            value = rs.read(String)
            result[key] = value
          end
        end
      end

      result
    end

    # Delete a metadata entry
    def delete(key : String) : Nil
      with_db do |db|
        db.exec("DELETE FROM metadata WHERE key = ?", key)
      end
    end
  end
end
