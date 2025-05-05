require "sqlite3"

module Data
  class Dataset
    property db : String

    def initialize(@db : String)

    end

    def list
      DB.open "sqlite3://./#{@db}" do |db|
        db.query("SELECT * FROM datasets") do |row|
          Log.info{ row }
        end
      end

    end
  end
end